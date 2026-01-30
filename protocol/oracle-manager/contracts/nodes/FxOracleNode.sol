// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "../storage/NodeDefinition.sol";
import "../storage/NodeOutput.sol";
import "../interfaces/external/IFxOracle.sol";

library FxOracleNode {
    function process(
        bytes memory parameters
    ) internal view returns (NodeOutput.Data memory nodeOutput, bytes memory possibleError) {
        (address fxOracleAddress, bytes32 feedId) = abi.decode(parameters, (address, bytes32));

        IFxOracle fxOracle = IFxOracle(fxOracleAddress);

        try fxOracle.getPrice(feedId) returns (IFxOracle.PriceData memory priceData) {
            nodeOutput = NodeOutput.Data(priceData.price, priceData.timestamp, 0, 0);
        } catch (bytes memory err) {
            possibleError = err;
        }
    }

    function isValid(NodeDefinition.Data memory nodeDefinition) internal view returns (bool valid) {
        if (nodeDefinition.parents.length > 0) {
            return false;
        }

        if (nodeDefinition.parameters.length != 32 * 2) {
            return false;
        }

        (address fxOracleAddress, bytes32 feedId) = abi.decode(
            nodeDefinition.parameters,
            (address, bytes32)
        );

        IFxOracle(fxOracleAddress).getPrice(feedId);

        return true;
    }
}
