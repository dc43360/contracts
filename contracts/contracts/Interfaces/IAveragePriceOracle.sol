//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IAveragePriceOracle {
    function getAverageMeadForOneEth()
        external
        view
        returns (uint256 amountOut);

    function updateMeadEthPrice() external;
}
