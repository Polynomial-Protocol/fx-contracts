// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";

interface IOracleManager {
    function registerNode(uint256 nodeType, bytes memory parameters, bytes32[] memory parents) external returns (bytes32 nodeId);
    function getNodeId(uint256 nodeType, bytes memory parameters, bytes32[] memory parents) external view returns (bytes32 nodeId);
    function process(bytes32 nodeId) external view returns (
        int256 price, 
        uint256 timestamp, 
        uint256 unused1, 
        uint256 unused2
    );
}

/**
 * @title RegisterNode
 * @notice Foundry script to register a trusted signer node with Oracle Manager
 * @dev Run with:
 *      forge script script/RegisterNode.s.sol:RegisterNode --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 *      
 *      Environment variables:
 *      - ORACLE_MANAGER_ADDRESS: Address of the Oracle Manager contract
 *      - TRUSTED_SIGNER_NODE_ADDRESS: Address of the TrustedSignerNode contract
 *      - ASSET_ID: Asset identifier (e.g., "ETH")
 *      - SIGNATURE_FILE: Path to file containing the signature data
 */
contract RegisterNode is Script {
    function run() public {
        // Get configuration from environment
        address oracleManager = vm.envAddress("ORACLE_MANAGER_ADDRESS");
        address trustedSignerNode = vm.envAddress("TRUSTED_SIGNER_NODE_ADDRESS");
        string memory assetId = vm.envString("ASSET_ID");
        string memory signatureFile = vm.envString("SIGNATURE_FILE");
        
        // Read the signature from file
        string memory signatureHex = vm.readFile(signatureFile);
        bytes memory signature = vm.parseBytes(signatureHex);
        
        console.log("Registering node for asset:", assetId);
        console.log("Oracle Manager:", oracleManager);
        console.log("Trusted Signer Node:", trustedSignerNode);
        
        // Encode the parameters for the external node
        bytes memory parameters = abi.encode(trustedSignerNode, assetId, signature);
        
        vm.startBroadcast();
        
        // Register the node with Oracle Manager (NodeType.EXTERNAL = 2)
        bytes32 nodeId = IOracleManager(oracleManager).registerNode(2, parameters, new bytes32[](0));
        
        vm.stopBroadcast();
        
        console.log("Node registered with ID:", vm.toString(nodeId));
        
        // Process the node to verify it works
        try IOracleManager(oracleManager).process(nodeId) returns (
            int256 price, 
            uint256 timestamp,
            uint256,
            uint256
        ) {
            console.log("Node processed successfully!");
            console.log("Price:", uint256(price));
            console.log("Timestamp:", timestamp);
        } catch Error(string memory reason) {
            console.log("Failed to process node:", reason);
        } catch {
            console.log("Failed to process node (unknown error)");
        }
        
        // Save the node ID to a file for future reference
        string memory outputFile = string.concat("node-", assetId, ".json");
        string memory jsonOutput = string.concat(
            '{"assetId":"', assetId, 
            '","nodeId":"', vm.toString(nodeId),
            '","oracleManager":"', vm.toString(oracleManager),
            '","trustedSignerNode":"', vm.toString(trustedSignerNode),
            '","timestamp":"', vm.toString(block.timestamp),
            '"}'
        );
        vm.writeFile(outputFile, jsonOutput);
        console.log("Node info saved to:", outputFile);
    }
} 