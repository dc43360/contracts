//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../Interfaces/IDwarf.sol";

contract MockContractDepositor {
    function depositOnDwarf(address dwarfAddress, address referralGiver)
        public
        payable
    {
        address[] memory token = new address[](0);
        uint256[] memory value = new uint256[](0);
        IDwarf DwarfInstance = IDwarf(dwarfAddress);
        DwarfInstance.deposit{value: msg.value}(
            referralGiver,
            token, token, value, value, 0, block.timestamp + 50
        );
    }
}
