// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";
import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";

import "../../storage/NodeDefinition.sol";
import "../../storage/NodeOutput.sol";
import "../../interfaces/external/IPythLazerWrapper.sol";

library PythLazerNode {
    using DecimalMath for int64;
    using SafeCastI256 for int256;

    int256 public constant PRECISION = 18;

    function process(
        bytes memory parameters
    ) internal view returns (NodeOutput.Data memory nodeOutput, bytes memory possibleError) {
        (address pythLazerWrapperAddress, uint32 feedId, uint256 stalenessTolerance) = abi.decode(
            parameters,
            (address, uint32, uint256)
        );

        IPythLazerWrapper pythLazerWrapper = IPythLazerWrapper(pythLazerWrapperAddress);

        try pythLazerWrapper.getLatestPrice(feedId, stalenessTolerance) returns (int256 price) {
            nodeOutput = NodeOutput.Data(price, block.timestamp, 0, 0);
        } catch (bytes memory err) {
            possibleError = err;
        }
    }

    function isValid(NodeDefinition.Data memory nodeDefinition) internal view returns (bool valid) {
        // Must have no parents
        if (nodeDefinition.parents.length > 0) {
            return false;
        }

        // Must have correct length of parameters data
        if (nodeDefinition.parameters.length != 32 * 3) {
            return false;
        }

        (address pythLazerWrapperAddress, uint32 feedId, uint256 stalenessTolerance) = abi.decode(
            nodeDefinition.parameters,
            (address, uint32, uint256)
        );

        IPythLazerWrapper pythLazerWrapper = IPythLazerWrapper(pythLazerWrapperAddress);

        // Must return relevant function without error
        pythLazerWrapper.getLatestPrice(feedId, stalenessTolerance);

        return true;
    }
}
