// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";
import "./utils/SignerUtils.sol";

/**
 * @title SignPrice
 * @notice Script to generate a signed price update that can be submitted to the oracle
 * @dev Run with:
 *      source .env
 *      forge script script/foundry/SignPrice.s.sol:SignPrice --rpc-url $POLYNOMIAL_SEPOLIA_RPC_URL
 */
contract SignPrice is Script {
    function run() public {
        // Input parameters
        string memory assetId = vm.envOr("ASSET_ID", string("ETH"));
        int256 price = int256(vm.envOr("PRICE", uint256(1500 ether))); // Default 1500 ETH
        uint256 signerPrivateKey = vm.envUint("ORACLE_SIGNER_KEY");
        
        // Get current timestamp or use provided one
        uint256 timestamp = vm.envOr("TIMESTAMP", uint256(block.timestamp));
        
        // Generate signed data
        bytes memory signedData = SignerUtils.createSignedPriceUpdate(
            assetId,
            price,
            timestamp,
            signerPrivateKey
        );
        
        // Create node parameters (for easy usage with the node)
        bytes memory nodeParameters = SignerUtils.createNodeParameters(
            assetId,
            signedData
        );
        
        // Output information
        address signerAddress = SignerUtils.getAddressFromPrivateKey(signerPrivateKey);
        
        // Log key information
        console.log("=== Signed Price Update ===");
        console.log("Asset ID: %s", assetId);
        console.log("Price: %d", price / 1e18); // Display in whole units
        console.log("Timestamp: %d", timestamp);
        console.log("Signer Address: %s", signerAddress);
        
        // Output the encoded data (can be used for direct testing or with API calls)
        console.log("\n=== Encoded Data (for API submission) ===");
        console.log("0x%s", vm.toString(signedData));
        
        // Output node parameters (can be used for direct interaction with the node contract)
        console.log("\n=== Node Parameters (for direct contract interaction) ===");
        console.log("0x%s", vm.toString(nodeParameters));
    }
} 