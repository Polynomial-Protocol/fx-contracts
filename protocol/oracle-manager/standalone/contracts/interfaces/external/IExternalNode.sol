// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "../../storage/NodeOutput.sol";

/**
 * @title IExternalNode
 * @notice Interface for external nodes in the oracle system
 */
interface IExternalNode {
    /**
     * @notice Process function that external nodes must implement
     * @param parentNodeOutputs Data from parent nodes, if any
     * @param parameters Parameters specific to this node
     * @param runtimeKeys Runtime keys for dynamic configuration
     * @param runtimeValues Runtime values corresponding to the keys
     * @return The processed node output
     */
    function process(
        NodeOutput.Data[] memory parentNodeOutputs,
        bytes memory parameters,
        bytes32[] memory runtimeKeys,
        bytes32[] memory runtimeValues
    ) external view returns (NodeOutput.Data memory);

    /**
     * @notice Validates parameters for this node type
     * @param parameters Parameters to validate
     * @return True if parameters are valid
     */
    function validateParameters(bytes memory parameters) external pure returns (bool);

    /**
     * @notice ERC-165 support for interface detection
     * @param interfaceId Interface identifier to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
