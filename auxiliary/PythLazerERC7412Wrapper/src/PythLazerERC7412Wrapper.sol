// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {AbstractProxy} from "@synthetixio/core-contracts/contracts/proxy/AbstractProxy.sol";
import {IERC7412} from "./interfaces/IERC7412.sol";
import {DecimalMath} from "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";
import {SafeCastI256} from "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import {IPythLazer} from "./interfaces/IPythLazer.sol";
import {PythLazerLib} from "./storage/PythLazerLib.sol";
import {Price} from "./storage/Price.sol";

contract PythLazerERC7412Wrapper is IERC7412, AbstractProxy {
    using DecimalMath for int64;
    using SafeCastI256 for int256;
    using Price for Price.Data;
    using PythLazerLib for bytes;

    int256 private constant PRECISION = 18;

    error NotSupported(uint8 updateType);
    error PropertyNotSupported();
    error FeedMismatch(uint8 feedIdGiven, uint8 feedIdExpected);
    error PriceTooStale(uint64 timestamp, uint64 minAcceptedPublishTime);

    address public immutable pythLazer;

    constructor(address _pythLazer) {
        pythLazer = _pythLazer;
    }

    function _getImplementation() internal view override returns (address) {
        return pythLazer;
    }

    function oracleId() external pure returns (bytes32) {
        return bytes32("PYTH_LAZER");
    }

    function getLatestPrice(
        uint32 feedId,
        uint256 stalenessTolerance
    ) external view returns (int256) {
        Price.Data storage priceData = Price.load(feedId);

        if (priceData.price > 0) {
            // solhint-disable-next-line numcast/safe-cast
            return _getScaledPrice(int64(priceData.price), priceData.exponent);
        }

        revert OracleDataRequired(
            // solhint-disable-next-line numcast/safe-cast
            address(this),
            abi.encode(
                // solhint-disable-next-line numcast/safe-cast
                uint8(1),
                // solhint-disable-next-line numcast/safe-cast
                uint64(stalenessTolerance),
                [feedId]
            )
        );
    }

    function getBenchmarkPrice(uint32 feedId, uint64 requestedTime) external view returns (int256) {
        uint256 benchmarkPrice = Price.load(feedId).benchmarkPrices[requestedTime];

        if (benchmarkPrice > 0) {
            // solhint-disable-next-line numcast/safe-cast
            return int256(benchmarkPrice);
        }

        revert OracleDataRequired(
            // solhint-disable-next-line numcast/safe-cast
            address(this),
            abi.encode(
                // solhint-disable-next-line numcast/safe-cast
                uint8(2), // PythQuery::Benchmark tag
                // solhint-disable-next-line numcast/safe-cast
                uint64(requestedTime),
                [feedId]
            )
        );
    }

    function fulfillOracleQuery(bytes memory signedOffchainData) external payable {
        IPythLazer PythLazer = IPythLazer(pythLazer);

        uint256 verificationFee = PythLazer.verification_fee();

        if (msg.value < verificationFee) {
            revert FeeRequired(verificationFee);
        }

        uint8 updateType = abi.decode(signedOffchainData, (uint8));

        if (updateType == 1 || updateType == 2) {
            (, uint64 stalenessTolerance, uint32[] memory priceIds, bytes memory updateData) = abi
                .decode(signedOffchainData, (uint8, uint64, uint32[], bytes));

            (bytes memory payload, ) = PythLazer.verifyUpdate{value: msg.value}(updateData);

            (uint64 timestamp, , uint8 feedsLen, uint16 pos) = payload.parsePayloadHeader();

            timestamp = timestamp / 1e6; // convert to seconds

            if (feedsLen != priceIds.length) {
                // solhint-disable-next-line numcast/safe-cast
                revert FeedMismatch(feedsLen, uint8(priceIds.length));
            }

            // solhint-disable-next-line numcast/safe-cast
            uint64 minAcceptedPublishTime = uint64(block.timestamp) - stalenessTolerance;

            if (timestamp < minAcceptedPublishTime) {
                revert PriceTooStale(timestamp, minAcceptedPublishTime);
            }

            for (uint8 i = 0; i < feedsLen; i++) {
                uint32 feedId;
                uint8 numProperties;
                (feedId, numProperties, pos) = payload.parseFeedHeader(pos);

                uint64 price;
                int16 exponent;

                for (uint8 j = 0; j < numProperties; j++) {
                    PythLazerLib.PriceFeedProperty property;
                    (property, pos) = payload.parseFeedProperty(pos);

                    if (property == PythLazerLib.PriceFeedProperty.Price) {
                        (price, pos) = payload.parseFeedValueUint64(pos);
                    } else if (property == PythLazerLib.PriceFeedProperty.Exponent) {
                        (exponent, pos) = payload.parseFeedValueInt16(pos);
                    } else {
                        revert PropertyNotSupported();
                    }
                }

                if (updateType == 1) {
                    Price.load(feedId).setPrice(price, timestamp, exponent);
                } else {
                    // solhint-disable-next-line numcast/safe-cast
                    Price.load(feedId).benchmarkPrices[timestamp] = uint256(
                        // solhint-disable-next-line numcast/safe-cast
                        _getScaledPrice(int64(price), exponent)
                    );
                }
            }
        } else {
            revert NotSupported(updateType);
        }
    }

    function _getScaledPrice(int64 price, int32 expo) private pure returns (int256) {
        int256 factor = PRECISION + expo;
        return factor > 0 ? price.upscale(factor.toUint()) : price.downscale((-factor).toUint());
    }
}
