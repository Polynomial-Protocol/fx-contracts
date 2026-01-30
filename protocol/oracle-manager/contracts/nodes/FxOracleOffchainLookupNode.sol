// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "../storage/NodeDefinition.sol";
import "../storage/NodeOutput.sol";

library FxOracleOffchainLookupNode {
    error OracleDataRequired(address oracleContract, bytes oracleQuery);

    function process(
        bytes memory parameters,
        bytes32[] memory runtimeKeys,
        bytes32[] memory runtimeValues
    ) internal pure returns (NodeOutput.Data memory nodeOutput, bytes memory possibleError) {
        (address fxOracleWrapperAddress, bytes32 feedId, uint256 stalenessTolerance) = abi.decode(
            parameters,
            (address, bytes32, uint256)
        );

        for (uint256 i = 0; i < runtimeKeys.length; i++) {
            if (runtimeKeys[i] == "stalenessTolerance") {
                // solhint-disable-next-line numcast/safe-cast
                stalenessTolerance = uint256(runtimeValues[i]);
            }
        }

        bytes32[] memory feedIds = new bytes32[](1);
        feedIds[0] = feedId;

        possibleError = abi.encodeWithSelector(
            OracleDataRequired.selector,
            fxOracleWrapperAddress,
            // solhint-disable-next-line numcast/safe-cast
            abi.encode(uint8(1), uint64(stalenessTolerance), feedIds)
        );
    }

    function isValid(NodeDefinition.Data memory nodeDefinition) internal pure returns (bool valid) {
        if (nodeDefinition.parents.length > 0) {
            return false;
        }

        if (nodeDefinition.parameters.length != 32 * 3) {
            return false;
        }

        abi.decode(nodeDefinition.parameters, (address, bytes32, uint256));

        return true;
    }
}
