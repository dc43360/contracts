//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../Config/BaseConfig.sol";

/// @title Dwarf strategy handler
/// @notice The contract keeps track of the liquidity pool balances, of the GHNY staking pool lp tokens and the GHNY staking pool mead rewards of a dwarf strategy investor using EIP-1973
/// @dev This contract is abstract and is intended to be inherited by dwarf.sol. Mead and lp rewards are handled using round masks
abstract contract DwarfStrategy is Initializable, BaseConfig {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct DwarfStrategyParticipant {
        uint256 amount;
        uint256 meadMask;
        uint256 pendingMead;
        uint256 lpMask;
        uint256 pendingLp;
        uint256 pendingAdditionalMead;
        uint256 additionalMeadMask;
    }

    uint256 public dwarfStrategyDeposits;

    uint256 public dwarfStrategyLastMeadBalance;
    uint256 public dwarfStrategyLastLpBalance;
    uint256 public dwarfStrategyLastAdditionalMeadBalance;

    uint256 private meadRoundMask;
    uint256 private lpRoundMask;
    uint256 private additionalMeadRoundMask;

    event DwarfStrategyClaimMeadEvent(
        address indexed user,
        uint256 meadAmount
    );
    event DwarfStrategyClaimLpEvent(
        address indexed user,
        uint256 meadAmount,
        uint256 bnbAmount
    );

    mapping(address => DwarfStrategyParticipant) private participantData;

    function __DwarfStrategy_init() internal initializer {
        meadRoundMask = 1;
        lpRoundMask = 1;
        additionalMeadRoundMask = 1;
    }

    /// @notice Deposits the desired amount for a dwarf strategy investor
    /// @dev User masks are updated before the deposit to have a clean state
    /// @param amount The desired deposit amount for an investor
    function dwarfStrategyDeposit(uint256 amount) internal {
        updateUserMask();
        participantData[msg.sender].amount += amount;
        dwarfStrategyDeposits += amount;
    }

    /// @notice Withdraws the desired amount for a dwarf strategy investor
    /// @dev User masks are updated before the deposit to have a clean state
    /// @param amount The desired withdraw amount for an investor
    function dwarfStrategyWithdraw(uint256 amount) internal {
        require(amount > 0, "TZ");
        require(amount <= getDwarfStrategyBalance(), "SD");

        updateUserMask();
        participantData[msg.sender].amount -= amount;
        dwarfStrategyDeposits -= amount;
    }

    /// @notice Stakes the mead rewards into the mead staking pool
    /// @param amount The mead reward to be staked
    function dwarfStrategyStakeMead(uint256 amount) internal {
        StakingPool.stake(amount);
    }

    /// @notice Updates the round mask for the mead and lp rewards
    /// @dev The mead and lp rewards are requested from the GHNY staking pool for the whole contract
    function updateRoundMasks() public {
        isNotPaused();
        if (dwarfStrategyDeposits == 0) return;

        // In order to keep track of how many new tokens were rewarded to this contract, we need to take
        // into account claimed tokens as well, otherwise the balance will become lower than "last balance"
        (
            ,
            ,
            ,
            ,
            uint256 claimedMead,
            uint256 claimedLp,
            ,
            ,
            uint256 claimedAdditionalMead
        ) = StakingPool.stakerAmounts(address(this));

        uint256 newMeadTokens = claimedMead +
            StakingPool.balanceOf(address(this)) -
            dwarfStrategyLastMeadBalance;
        uint256 newLpTokens = claimedLp +
            StakingPool.lpBalanceOf(address(this)) -
            dwarfStrategyLastLpBalance;
        uint256 newAdditionalMeadTokens = claimedAdditionalMead +
            StakingPool.getPendingMeadRewards() -
            dwarfStrategyLastAdditionalMeadBalance;

        dwarfStrategyLastMeadBalance += newMeadTokens;
        dwarfStrategyLastLpBalance += newLpTokens;
        dwarfStrategyLastAdditionalMeadBalance += newAdditionalMeadTokens;

        meadRoundMask +=
            (DECIMAL_OFFSET * newMeadTokens) /
            dwarfStrategyDeposits;
        lpRoundMask += (DECIMAL_OFFSET * newLpTokens) / dwarfStrategyDeposits;
        additionalMeadRoundMask +=
            (DECIMAL_OFFSET * newAdditionalMeadTokens) /
            dwarfStrategyDeposits;
    }

    /// @notice Updates the user round mask for the mead and lp rewards
    function updateUserMask() internal {
        updateRoundMasks();

        participantData[msg.sender].pendingMead +=
            ((meadRoundMask - participantData[msg.sender].meadMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender].meadMask = meadRoundMask;

        participantData[msg.sender].pendingLp +=
            ((lpRoundMask - participantData[msg.sender].lpMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender].lpMask = lpRoundMask;

        participantData[msg.sender].pendingAdditionalMead +=
            ((additionalMeadRoundMask -
                participantData[msg.sender].additionalMeadMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender]
            .additionalMeadMask = additionalMeadRoundMask;
    }

    /// @notice Claims the staked mead for an investor. The investors honnies are first unstaked from the GHNY staking pool and then transfered to the investor.
    /// @dev The investors mead mask is updated to the current mead round mask and the pending honeies are paid out
    /// @dev Can be called static to get the current investors pending Mead
    /// @return the pending Mead
    function dwarfStrategyClaimMead() public returns (uint256) {
        isNotPaused();
        updateRoundMasks();
        uint256 pendingMead = participantData[msg.sender].pendingMead +
            ((meadRoundMask - participantData[msg.sender].meadMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender].meadMask = meadRoundMask;

        if (pendingMead > 0) {
            participantData[msg.sender].pendingMead = 0;
            StakingPool.unstake(pendingMead);

            IERC20Upgradeable(address(MeadToken)).safeTransfer(
                msg.sender,
                pendingMead
            );
        }
        emit DwarfStrategyClaimMeadEvent(msg.sender, pendingMead);
        return pendingMead;
    }

    /// @notice Claims the staked lp tokens for an investor. The investors lps are first unstaked from the GHNY staking pool and then transfered to the investor.
    /// @dev The investors lp mask is updated to the current lp round mask and the pending lps are paid out
    /// @dev Can be called static to get the current investors pending LP
    /// @return claimedMead The claimed mead amount
    /// @return claimedBnb The claimed bnb amount
    function dwarfStrategyClaimLP()
        public
        returns (uint256 claimedMead, uint256 claimedBnb)
    {
        isNotPaused();
        updateRoundMasks();
        uint256 pendingLp = participantData[msg.sender].pendingLp +
            ((lpRoundMask - participantData[msg.sender].lpMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender].lpMask = lpRoundMask;

        uint256 pendingAdditionalMead = participantData[msg.sender]
            .pendingAdditionalMead +
            ((additionalMeadRoundMask -
                participantData[msg.sender].additionalMeadMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;

        participantData[msg.sender]
            .additionalMeadMask = additionalMeadRoundMask;

        uint256 _claimedMead = 0;
        uint256 _claimedBnb = 0;
        if (pendingLp > 0 || pendingAdditionalMead > 0) {
            participantData[msg.sender].pendingLp = 0;
            participantData[msg.sender].pendingAdditionalMead = 0;
            (_claimedMead, _claimedBnb) = StakingPool.claimLpTokens(
                pendingLp,
                pendingAdditionalMead,
                msg.sender
            );
        }
        emit DwarfStrategyClaimLpEvent(
            msg.sender,
            _claimedMead,
            _claimedBnb
        );
        return (_claimedMead, _claimedBnb);
    }

    /// @notice Gets the current dwarf strategy balance from the liquidity pool
    /// @return The current dwarf strategy balance for the investor
    function getDwarfStrategyBalance() public view returns (uint256) {
        return participantData[msg.sender].amount;
    }

    /// @notice Gets the current staked mead for a dwarf strategy investor
    /// @dev Gets the current mead balance from the GHNY staking pool to calculate the current mead round mask. This is then used to calculate the total pending mead for the investor
    /// @return The current mead balance for a dwarf investor
    function getDwarfStrategyStakedMead() public view returns (uint256) {
        if (
            participantData[msg.sender].meadMask == 0 ||
            dwarfStrategyDeposits == 0
        ) return 0;

        (, , , , uint256 claimedMead, , , , ) = StakingPool.stakerAmounts(
            address(this)
        );

        uint256 newMeadTokens = claimedMead +
            StakingPool.balanceOf(address(this)) -
            dwarfStrategyLastMeadBalance;
        uint256 currentMeadRoundMask = meadRoundMask +
            (DECIMAL_OFFSET * newMeadTokens) /
            dwarfStrategyDeposits;

        return
            participantData[msg.sender].pendingMead +
            ((currentMeadRoundMask - participantData[msg.sender].meadMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;
    }

    /// @notice Gets the current staked lps for a dwarf strategy investor
    /// @dev Gets the current lp balance from the GHNY staking pool to calculate the current lp round mask. This is then used to calculate the total pending lp for the investor
    /// @return The current lp balance for a dwarf investor
    function getDwarfStrategyLpRewards() external view returns (uint256) {
        if (
            participantData[msg.sender].lpMask == 0 ||
            dwarfStrategyDeposits == 0
        ) return 0;

        (, , , , , uint256 claimedLp, , , ) = StakingPool.stakerAmounts(
            address(this)
        );

        uint256 newLpTokens = claimedLp +
            StakingPool.lpBalanceOf(address(this)) -
            dwarfStrategyLastLpBalance;
        uint256 currentLpRoundMask = lpRoundMask +
            (DECIMAL_OFFSET * newLpTokens) /
            dwarfStrategyDeposits;

        return
            participantData[msg.sender].pendingLp +
            ((currentLpRoundMask - participantData[msg.sender].lpMask) *
                participantData[msg.sender].amount) /
            DECIMAL_OFFSET;
    }

    /// @notice Reads out the participant data
    /// @param participant The address of the participant
    /// @return Participant data
    function getDwarfStrategyParticipantData(address participant)
        external
        view
        returns (DwarfStrategyParticipant memory)
    {
        return participantData[participant];
    }

    uint256[50] private __gap;
}
