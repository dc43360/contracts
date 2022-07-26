//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../Interfaces/IUniswapV2Pair.sol";
import "../Interfaces/IAveragePriceOracle.sol";

/// @notice This oracle calculates the average price of the Mead BNB liquidity pool. The time period can be set for the average price window. The larger the price window is set, the riskier it is for an attacker to manipulate the price using e.q. a flash loan attack. However, the larger the price window, the less current the Mead-BNB price
/// @dev The amount out in Mead for one BNB is the Bee Efficiency Level (BEL).
/// @dev Implementation based on (Fixed windows): https://docs.uniswap.org/protocol/V2/guides/smart-contract-integration/building-an-oracle
contract AveragePriceOracle is
    Initializable,
    IAveragePriceOracle,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    // 30 seconds average price window
    uint32 constant TIME_PERIOD = 30;
    uint224 constant Q112 = 2**112;

    uint256 private blockTimestampLast;
    uint224 private meadEthPriceAverage;
    uint256 private meadEthCumulativeLast;
    bool private meadIsToken0;

    IERC20Upgradeable private MeadToken;
    IUniswapV2Pair private MeadBnbLpToken;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function initialize(
        address _meadTokenAddress,
        address _meadBnbLpToken,
        address _admin
    ) public initializer {
        require(
            IUniswapV2Pair(_meadBnbLpToken).token0() == _meadTokenAddress ||
                IUniswapV2Pair(_meadBnbLpToken).token1() == _meadTokenAddress,
            "LA"
        );
        MeadToken = IERC20Upgradeable(_meadTokenAddress);
        MeadBnbLpToken = IUniswapV2Pair(_meadBnbLpToken);
        meadIsToken0 = MeadBnbLpToken.token0() == _meadTokenAddress;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        __Pausable_init();
    }

    /// @notice pause
    /// @dev pause the contract
    function pause() external whenNotPaused onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice unpause
    /// @dev unpause the contract
    function unpause() external whenPaused onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice gets the average amount of Mead Token out for one BNB
    /// @dev uses the average price oracle to calculate the price
    /// @return amountOut the amount out in Mead Token for one BNB
    function getAverageMeadForOneEth()
        public
        view
        override
        returns (uint256 amountOut)
    {
        return (meadEthPriceAverage * 1e18) / Q112;
    }

    /// @notice Updates the average Mead BNB price
    /// @dev Needs to be called periodically such that the price updates. Should always be called before the average price is used. The first time called, the values are initialized.
    function updateMeadEthPrice() external override whenNotPaused {
        (
            uint256 _price0Cumulative,
            uint256 _price1Cumulative,
            uint32 _blockTimestamp
        ) = currentCumulativePrices(MeadBnbLpToken);

        // initialized the first time called
        if (blockTimestampLast == 0) {
            (
                uint112 _reserve0,
                uint112 _reserve1,
                uint32 _blockTimestampLast
            ) = MeadBnbLpToken.getReserves();

            if (meadIsToken0) {
                meadEthPriceAverage = (Q112 * _reserve0) / _reserve1;
                meadEthCumulativeLast = _price1Cumulative;
            } else {
                meadEthPriceAverage = (Q112 * _reserve1) / _reserve0;
                meadEthCumulativeLast = _price0Cumulative;
            }
            blockTimestampLast = _blockTimestamp;
            return;
        }

        uint256 _timeElapsed = _blockTimestamp - blockTimestampLast;

        if (_timeElapsed >= TIME_PERIOD) {
            if (meadIsToken0) {
                meadEthPriceAverage = uint224(
                    (_price1Cumulative - meadEthCumulativeLast) / _timeElapsed
                );
                meadEthCumulativeLast = _price1Cumulative;
            } else {
                meadEthPriceAverage = uint224(
                    (_price0Cumulative - meadEthCumulativeLast) / _timeElapsed
                );
                meadEthCumulativeLast = _price0Cumulative;
            }
            blockTimestampLast = _blockTimestamp;
        }
    }

    /// @notice Gets the current block timestamp in uint32 format
    /// @return The current timestamp
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2**32);
    }

    /// @notice Gets the current cumulative prices
    /// @dev This function takes the cumulative prices from the pair LP token and adds the accumulated price since the last update of the average price.
    /// @param pair The LP pair to receive the cumulative prices
    /// @return _price0Cumulative The cumulative price for token 0
    /// @return _price1Cumulative The cumulative price for token 1
    /// @return _blockTimestamp The timestamp for the respective cumulative prices
    function currentCumulativePrices(IUniswapV2Pair pair)
        internal
        view
        returns (
            uint256 _price0Cumulative,
            uint256 _price1Cumulative,
            uint32 _blockTimestamp
        )
    {
        _blockTimestamp = currentBlockTimestamp();
        _price0Cumulative = pair.price0CumulativeLast();
        _price1Cumulative = pair.price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        ) = pair.getReserves();
        if (_blockTimestampLast != _blockTimestamp) {
            uint32 _timeElapsed = _blockTimestamp - _blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            _price0Cumulative += uint256(
                ((Q112 * _reserve1) / _reserve0) * _timeElapsed
            );
            // counterfactual
            _price1Cumulative += uint256(
                ((Q112 * _reserve0) / _reserve1) * _timeElapsed
            );
        }
    }

    uint256[50] private __gap;
}
