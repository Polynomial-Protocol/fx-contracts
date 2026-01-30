//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

interface IFxOracle {
    struct PriceData {
        int256 price;
        uint256 timestamp;
    }

    function getPrice(bytes32 feedId) external view returns (PriceData memory);
}
