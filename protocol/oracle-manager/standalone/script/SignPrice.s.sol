// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

/**
 * @title SignPrice
 * @notice A script to sign price data for the Trusted Signer Oracle
 * @dev Run with:
 *      forge script script/SignPrice.s.sol:SignPrice --private-key <your_private_key>
 *      
 *      Environment variables:
 *      - ASSET_ID: Asset identifier (e.g., "ETH")
 *      - PRICE: Price in wei (with 18 decimals, e.g., 3500000000000000000000 for ETH at $3500)
 *      - TIMESTAMP: Timestamp for the price (optional, defaults to current time)
 */
contract SignPrice is Script {
    function run() public {
        // Read input from environment variables
        string memory assetId = vm.envString("ASSET_ID");
        int256 price = int256(vm.envUint("PRICE"));
        uint256 timestamp = vm.envOr("TIMESTAMP", uint256(block.timestamp));
        
        // Get private key for signing - forge automatically sets this from --private-key
        uint256 privateKey = uint256(vm.envOr("FOUNDRY_PRIVATE_KEY", bytes32(0)));
        address signer = vm.addr(privateKey);
        
        // Log the data that will be signed
        console.log("Signing price data:");
        console.log("Asset ID: ", assetId);
        console.log("Price: ", uint256(price));
        console.log("Timestamp: ", timestamp);
        console.log("Signer: ", signer);
        
        // Create the message hash
        bytes32 messageHash = keccak256(abi.encodePacked(assetId, price, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode the price data
        bytes memory priceData = abi.encode(price, timestamp);
        
        // Combine into the complete signed data
        bytes memory signedData = bytes.concat(priceData, signature);
        
        // Create the parameters for the node
        bytes memory parameters = abi.encode(assetId, signedData);
        
        // Output the results
        console.log("\nMessage hash: ", vm.toString(messageHash));
        console.log("Ethereum signed message hash: ", vm.toString(ethSignedMessageHash));
        
        console.log("\nSignature (r, s, v): ");
        console.log("r: ", vm.toString(r));
        console.log("s: ", vm.toString(s));
        console.log("v: ", v);
        
        console.log("\nEncoded data for Oracle (hex):");
        console.log("Price data: 0x", vm.toString(priceData));
        console.log("Complete signed data: 0x", vm.toString(signedData));
        console.log("Node parameters: 0x", vm.toString(parameters));
        
        // Output a final message indicating success
        console.log("\nSignature generation complete!");
        console.log("To use this data, copy the 'Complete signed data' value above into your client application.");
    }
} 