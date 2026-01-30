// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {AbstractProxy} from "@synthetixio/core-contracts/contracts/proxy/AbstractProxy.sol";
import {IERC7412} from "./interfaces/IERC7412.sol";
import {IFxOracle} from "./interfaces/IFxOracle.sol";
import {Price} from "./storage/Price.sol";

contract FxOracleERC7412Wrapper is IERC7412, AbstractProxy {
    error NotSupported(uint8 updateType);

    // solhint-disable-next-line immutable-vars-naming
    address public immutable fxOracleAddress;

    constructor(address _fxOracleAddress) {
        fxOracleAddress = _fxOracleAddress;
    }

    function _getImplementation() internal view override returns (address) {
        return fxOracleAddress;
    }

    function oracleId() external pure returns (bytes32) {
        return bytes32("FX_ORACLE");
    }

    function getLatestPrice(
        bytes32 feedId,
        uint256 stalenessTolerance
    ) external view returns (int256) {
        IFxOracle fxOracle = IFxOracle(fxOracleAddress);
        IFxOracle.PriceData memory priceData = fxOracle.getPrice(feedId);

        if (block.timestamp <= stalenessTolerance + priceData.timestamp) {
            return priceData.price;
        }

        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = feedId;

        revert OracleDataRequired(
            address(this),
            // solhint-disable-next-line numcast/safe-cast
            abi.encode(uint8(1), uint64(stalenessTolerance), feedIds)
        );
    }

    function getBenchmarkPrice(
        bytes32 feedId,
        uint64 requestedTime
    ) external view returns (int256) {
        int256 benchmarkPrice = Price.load(feedId).benchmarkPrices[requestedTime];

        if (benchmarkPrice != 0) {
            return benchmarkPrice;
        }

        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = feedId;

        revert OracleDataRequired(
            address(this),
            // solhint-disable-next-line numcast/safe-cast
            abi.encode(uint8(2), uint64(requestedTime), feedIds)
        );
    }

    function fulfillOracleQuery(bytes memory signedOffchainData) external payable {
        IFxOracle fxOracle = IFxOracle(fxOracleAddress);

        uint8 updateType = abi.decode(signedOffchainData, (uint8));

        if (updateType == 1) {
            (, , bytes32[] memory feedIds, IFxOracle.PriceUpdate[] memory updates) = abi.decode(
                signedOffchainData,
                (uint8, uint64, bytes32[], IFxOracle.PriceUpdate[])
            );

            if (updates.length == 1) {
                fxOracle.updatePrice(
                    updates[0].feedId,
                    updates[0].price,
                    updates[0].timestamp,
                    updates[0].signature
                );
            } else if (updates.length > 1) {
                fxOracle.updatePrices(updates);
            }
        } else if (updateType == 2) {
            (
                ,
                uint64 timestamp,
                bytes32[] memory feedIds,
                IFxOracle.PriceUpdate[] memory updates
            ) = abi.decode(signedOffchainData, (uint8, uint64, bytes32[], IFxOracle.PriceUpdate[]));

            for (uint256 i = 0; i < updates.length; i++) {
                fxOracle.updatePrice(
                    updates[i].feedId,
                    updates[i].price,
                    updates[i].timestamp,
                    updates[i].signature
                );

                Price.load(updates[i].feedId).benchmarkPrices[timestamp] = updates[i].price;
            }
        } else {
            revert NotSupported(updateType);
        }
    }
}
