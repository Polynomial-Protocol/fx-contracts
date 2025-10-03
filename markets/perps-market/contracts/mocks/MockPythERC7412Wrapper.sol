//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

contract MockPythERC7412Wrapper {
    bool public alwaysRevert;
    int256 public price;

    // Match the interface error signature
    error OracleDataRequired(address oracleContract, bytes oracleQuery);

    function setBenchmarkPrice(int256 _price) external {
        price = _price;
        alwaysRevert = false;
    }

    function setAlwaysRevertFlag(bool _alwaysRevert) external {
        alwaysRevert = _alwaysRevert;
    }

    function getBenchmarkPrice(
        bytes32 /* priceId */,
        uint64 /* requestedTime */
    ) external view returns (int256) {
        if (alwaysRevert) {
            revert OracleDataRequired(address(this), "");
        }

        return price;
    }

    function getLatestPrice(
        bytes32 /* priceId */,
        uint256 /* stalenessTolerance */
    ) external view returns (int256) {
        if (alwaysRevert) {
            revert OracleDataRequired(address(this), "");
        }

        return price;
    }
}
