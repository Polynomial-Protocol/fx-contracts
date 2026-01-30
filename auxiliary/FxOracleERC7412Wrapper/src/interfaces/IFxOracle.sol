// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

interface IFxOracle {
    struct PriceData {
        int256 price;
        uint256 timestamp;
    }

    struct PriceUpdate {
        bytes32 feedId;
        int256 price;
        uint256 timestamp;
        bytes signature;
    }

    function getPrice(bytes32 feedId) external view returns (PriceData memory);

    function updatePrice(
        bytes32 feedId,
        int256 price,
        uint256 timestamp,
        bytes calldata signature
    ) external;

    function updatePrices(PriceUpdate[] calldata updates) external;
}
