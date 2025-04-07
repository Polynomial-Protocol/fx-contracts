// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../contracts/TrustedSignerNode.sol";

/**
 * @title RegisterTrustedSignerNode
 * @notice A script to register a TrustedSignerNode with the Oracle Manager
 * @dev Run with:
 *      forge script script/RegisterTrustedSignerNode.s.sol:RegisterTrustedSignerNode --rpc-url <RPC_URL> --broadcast
 *      
 *      Environment variables:
 *      - NODE_ADDRESS: Address of the deployed TrustedSignerNode
 *      - ORACLE_MANAGER_ADDRESS: Address of the Oracle Manager contract
 *      - NODE_ID: Unique identifier for the node (e.g., "trusted-signer-eth-usd")
 *      - ASSET_ID: Asset identifier (e.g., "ETH")
 *      - PRIVATE_KEY: Private key for deployment
 */
contract RegisterTrustedSignerNode is Script {
    function run() public {
        address nodeAddress = vm.envAddress("NODE_ADDRESS");
        address oracleManagerAddress = vm.envAddress("ORACLE_MANAGER_ADDRESS");
        string memory nodeId = vm.envString("NODE_ID");
        string memory assetId = vm.envString("ASSET_ID");
        
        console.log("Registering TrustedSignerNode with Oracle Manager");
        console.log("Node address:", nodeAddress);
        console.log("Oracle Manager address:", oracleManagerAddress);
        console.log("Node ID:", nodeId);
        console.log("Asset ID:", assetId);
        
        // Encode parameters for registration
        bytes memory parameters = abi.encode(assetId);
        
        vm.startBroadcast();
        
        // This is a mock call - in a real implementation, you would call the Oracle Manager's
        // registerExternalNode method with these parameters
        console.log("\nTo register this node, call registerExternalNode on the Oracle Manager with:");
        console.log("nodeId:", nodeId);
        console.log("implementation:", nodeAddress);
        console.log("parameters:", vm.toString(parameters));
        
        // Example call (commented out - replace with actual Oracle Manager interface)
        // IOracleManager oracleManager = IOracleManager(oracleManagerAddress);
        // bytes32 nodeIdBytes = keccak256(abi.encodePacked(nodeId));
        // oracleManager.registerExternalNode(nodeIdBytes, nodeAddress, parameters);
        // console.log("Node registered with ID:", nodeId);
        
        vm.stopBroadcast();
        
        console.log("\nRegistration command information complete!");
    }
} 