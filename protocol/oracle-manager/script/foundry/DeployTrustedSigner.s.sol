// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";
import "../../contracts/nodes/external-nodes/TrustedSignerRegistry.sol";
import "../../contracts/nodes/external-nodes/TrustedSignerNode.sol";

/**
 * @title DeployTrustedSigner
 * @notice Deployment script for the Trusted Signer Oracle
 * @dev Run with:
 *      source .env
 *      forge script script/foundry/DeployTrustedSigner.s.sol:DeployTrustedSigner --rpc-url $POLYNOMIAL_SEPOLIA_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast --verify
 */
contract DeployTrustedSigner is Script {
    function run() public {
        // Retrieve private key and signer address from env
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address signerAddress = vm.envAddress("ORACLE_SIGNER_ADDRESS");
        
        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy registry
        TrustedSignerRegistry registry = new TrustedSignerRegistry();
        console.log("TrustedSignerRegistry deployed at:", address(registry));
        
        // Deploy node
        TrustedSignerNode node = new TrustedSignerNode(address(registry));
        console.log("TrustedSignerNode deployed at:", address(node));
        
        // Authorize the signer
        registry.authorizeSigner(signerAddress);
        console.log("Authorized signer:", signerAddress);
        
        // End broadcast
        vm.stopBroadcast();
        
        // Log deployment details to console
        console.log("Deployment completed successfully");
        console.log("Network: Polynomial Sepolia");
        console.log("=== Contract Addresses ===");
        console.log("TrustedSignerRegistry:", address(registry));
        console.log("TrustedSignerNode:", address(node));
        console.log("=== Configuration ===");
        console.log("Authorized Signer:", signerAddress);
    }
} 