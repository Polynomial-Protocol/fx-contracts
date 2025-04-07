// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";

/**
 * @title FetchFundingRate
 * @notice Foundry script to fetch Binance funding rates and sign them
 * @dev This script uses Foundry's cheatcodes to make an HTTP request to Binance API
 *      and signs the result with the provided private key.
 *      
 *      Run with:
 *      forge script script/binance/FetchFundingRate.s.sol:FetchFundingRate --private-key $PRIVATE_KEY
 *      
 *      Environment variables:
 *      - PRIVATE_KEY: Private key of the signer (required)
 *      - SYMBOL: Trading pair symbol (default: "BTCUSDT")
 */
contract FetchFundingRate is Script {
    string public constant ASSET_ID = "BTC-FUNDING-RATE";
    string public constant BINANCE_API_URL = "https://fapi.binance.com/fapi/v1/fundingRate";
    
    struct FundingRateResponse {
        string symbol;
        string fundingRate;
        uint256 fundingTime;
    }
    
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        string memory symbol = vm.envOr("SYMBOL", string("BTCUSDT"));
        
        // Construct the API URL with query parameters
        string memory url = string.concat(
            BINANCE_API_URL,
            "?symbol=",
            symbol,
            "&limit=1"
        );
        
        console.log("Fetching funding rate for:", symbol);
        console.log("URL:", url);
        
        // Make the HTTP request to Binance API
        string[] memory headers = new string[](0);
        bytes memory response = vm.ffi(
            ["curl", "-s", url]
        );
        
        // Parse the response (first turn bytes to string)
        string memory responseStr = string(response);
        
        // Extract funding rate and timestamp using string operations
        // Note: In a real implementation, this would be done with a proper JSON parser
        // For demo purposes, we extract it using string operations
        int256 fundingRate;
        uint256 fundingTime;
        
        // Log the raw response for debugging
        console.log("Response:", responseStr);
        
        // For demo purposes, we'll use fixed values
        // In a real implementation, parse the JSON response
        fundingRate = 0.0001 ether; // 0.01% as example
        fundingTime = block.timestamp;
        
        console.log("Extracted funding rate:", fundingRate);
        console.log("Funding time:", fundingTime);
        
        // Create the message hash (assetId + fundingRate + timestamp)
        bytes32 messageHash = keccak256(abi.encodePacked(ASSET_ID, fundingRate, fundingTime));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Sign the message hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode the funding rate data
        bytes memory encodedData = abi.encode(fundingRate, fundingTime);
        
        // Combine into the complete signature
        bytes memory completeSignature = bytes.concat(encodedData, signature);
        
        // Calculate signer address for verification
        address signer = ecrecover(ethSignedMessageHash, v, r, s);
        
        // Output the signature details
        console.log("Signer address:", signer);
        console.log("Complete signature:");
        console.logBytes(completeSignature);
        
        // Write to files for later use
        string memory filePath = string.concat("signature-", ASSET_ID, ".txt");
        vm.writeFile(filePath, vm.toString(completeSignature));
        console.log("Signature written to:", filePath);
        
        // Write JSON file with complete information
        string memory jsonPath = string.concat("signature-", ASSET_ID, ".json");
        string memory jsonData = string.concat(
            '{"assetId":"', ASSET_ID,
            '","fundingRate":"', vm.toString(uint256(fundingRate)),
            '","timestamp":"', vm.toString(fundingTime),
            '","symbol":"', symbol,
            '","signer":"', vm.toString(signer),
            '","signature":"0x', vm.toString(bytes32(uint256(keccak256(completeSignature)))),
            '"}'
        );
        vm.writeFile(jsonPath, jsonData);
        console.log("Signature JSON written to:", jsonPath);
    }
} 