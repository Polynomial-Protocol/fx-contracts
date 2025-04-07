// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";

/**
 * @title SignPrice
 * @notice Foundry script to generate signed price data for the Trusted Signer Oracle
 * @dev Run with:
 *      forge script script/SignPrice.s.sol:SignPrice --private-key $PRIVATE_KEY
 *      
 *      Environment variables:
 *      - PRIVATE_KEY: Private key of the signer (required)
 *      - ASSET_ID: Asset identifier (e.g., "ETH")
 *      - PRICE: Price in wei (with 18 decimals, e.g., 3500000000000000000000 for ETH at $3500)
 */
contract SignPrice is Script {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        string memory assetId = vm.envString("ASSET_ID");
        int256 price = int256(vm.envUint("PRICE"));
        uint256 timestamp = block.timestamp;
        
        // Log the data that will be signed
        console.log("Signing price data for asset:", assetId);
        console.log("Price:", uint256(price));
        console.log("Timestamp:", timestamp);
        
        // Create the message hash (assetId + price + timestamp)
        bytes32 messageHash = keccak256(abi.encodePacked(assetId, price, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Sign the message hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode the price data
        bytes memory encodedData = abi.encode(price, timestamp);
        
        // Combine into the complete signature
        bytes memory completeSignature = bytes.concat(encodedData, signature);
        
        // Calculate signer address for verification
        address signer = ecrecover(ethSignedMessageHash, v, r, s);
        
        // Output the signature details
        console.log("Signer address:", signer);
        console.log("Complete signature:");
        console.logBytes(completeSignature);
        
        // Write to a file for later use
        string memory filePath = string.concat("signature-", assetId, ".txt");
        vm.writeFile(filePath, vm.toString(completeSignature));
        console.log("Signature written to:", filePath);
        
        // Write JSON file with complete information
        string memory jsonPath = string.concat("signature-", assetId, ".json");
        string memory jsonData = string.concat(
            '{"assetId":"', assetId,
            '","price":"', vm.toString(uint256(price)),
            '","timestamp":"', vm.toString(timestamp),
            '","humanReadableTime":"', vm.toString(timestamp), // Would be nicer with datetime formatting
            '","signer":"', vm.toString(signer),
            '","signature":"0x', vm.toString(bytes32(uint256(keccak256(completeSignature)))), // Hash for brevity
            '"}'
        );
        vm.writeFile(jsonPath, jsonData);
        console.log("Signature JSON written to:", jsonPath);
    }
} 