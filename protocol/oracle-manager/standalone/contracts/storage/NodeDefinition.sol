// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

/**
 * @title NodeDefinition
 * @notice Simple structure for node definitions in the standalone oracle system
 */
library NodeDefinition {
    /**
     * @notice Structure to define a node
     */
    struct Data {
        // The type of node
        uint256 nodeType;
        
        // Parameters for the node
        bytes parameters;
        
        // Parent nodes
        bytes32[] parents;
    }
    
    // Node type definitions
    uint256 constant REDUCER_NODE = 1;
    uint256 constant EXTERNAL_NODE = 2;
    uint256 constant CHAINLINK_NODE = 3;
    uint256 constant UNISWAP_NODE = 4;
    uint256 constant PYTH_NODE = 5;
    uint256 constant PRICE_DEVIATION_CIRCUIT_BREAKER_NODE = 6;
    uint256 constant STALENESS_CIRCUIT_BREAKER_NODE = 7;
    uint256 constant CONSTANT_NODE = 8;
}
