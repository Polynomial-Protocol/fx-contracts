// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";
import "../contracts/nodes/external-nodes/TrustedSignerRegistry.sol";
import "../contracts/nodes/external-nodes/TrustedSignerNode.sol";

/**
 * @title DeployTrustedSignerOracle
 * @notice Foundry script to deploy the Trusted Signer Oracle system
 * @dev Run with:
 *      forge script script/DeployTrustedSignerOracle.s.sol:DeployTrustedSignerOracle --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract DeployTrustedSignerOracle is Script {
    // Configuration (can override with env vars)
    string public constant ENV_SIGNER_ADDRESS = "SIGNER_ADDRESS";
    
    function run() public {
        // Get signer address from environment or use deployer
        address signerAddress = vm.envOr(ENV_SIGNER_ADDRESS, address(0));
        if (signerAddress == address(0)) {
            // If not specified, use the deployer's address
            signerAddress = vm.addr(vm.envUint("PRIVATE_KEY"));
        }
        
        console.log("Deploying Trusted Signer Oracle contracts");
        console.log("Authorized signer address:", signerAddress);
        
        vm.startBroadcast();
        
        // Deploy TrustedSignerRegistry
        TrustedSignerRegistry registry = new TrustedSignerRegistry();
        console.log("TrustedSignerRegistry deployed at:", address(registry));
        
        // Authorize the signer
        registry.authorizeSigner(signerAddress);
        console.log("Signer authorized in registry");
        
        // Deploy TrustedSignerNode
        TrustedSignerNode node = new TrustedSignerNode(address(registry));
        console.log("TrustedSignerNode deployed at:", address(node));
        
        vm.stopBroadcast();
        
        console.log("\nDeployment complete!");
        console.log("TrustedSignerRegistry:", address(registry));
        console.log("TrustedSignerNode:", address(node));
        console.log("Authorized signer:", signerAddress);
    }
} 