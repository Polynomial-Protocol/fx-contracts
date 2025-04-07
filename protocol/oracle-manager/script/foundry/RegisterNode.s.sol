// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";
import "../../contracts/interfaces/IOracleManager.sol";

/**
 * @title RegisterNode
 * @notice Script to register the TrustedSignerNode with the OracleManager
 * @dev Run with:
 *      source .env
 *      forge script script/foundry/RegisterNode.s.sol:RegisterNode --rpc-url $POLYNOMIAL_SEPOLIA_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast
 */
contract RegisterNode is Script {
    function run() public {
        // Retrieve private key from env
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        // Load contract addresses from environment
        address oracleManagerAddress = vm.envAddress("ORACLE_MANAGER_ADDRESS");
        address trustedSignerNodeAddress = vm.envAddress("TRUSTED_SIGNER_NODE_ADDRESS");
        
        // Create interface
        IOracleManager oracleManager = IOracleManager(oracleManagerAddress);
        
        // Node registration parameters
        string memory assetId = "ETH"; // Example asset, can be customized
        
        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);
        
        // Register the node
        bytes32 nodeId = oracleManager.registerExternalNode(
            trustedSignerNodeAddress,
            abi.encode(assetId), // Parameters to validate
            new bytes32[](0),    // No parent nodes
            new address[](0)     // No imports
        );
        
        // End broadcast
        vm.stopBroadcast();
        
        // Log registration details
        console.log("Node registration successful");
        console.log("Network: Polynomial Sepolia");
        console.log("=== Registration Details ===");
        console.log("Oracle Manager: %s", oracleManagerAddress);
        console.log("TrustedSignerNode: %s", trustedSignerNodeAddress);
        console.log("Node ID: %s", vm.toString(nodeId));
        console.log("Asset ID: %s", assetId);
    }
} 