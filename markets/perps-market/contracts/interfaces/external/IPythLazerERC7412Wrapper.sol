// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

interface IPythLazerERC7412Wrapper {
    error OracleDataRequired(address oracleContract, bytes oracleQuery);

    function getBenchmarkPrice(uint32 feedId, uint64 requestedTime) external view returns (int256);

    function getLatestPrice(
        uint32 feedId,
        uint256 stalenessTolerance
    ) external view returns (int256);
}
