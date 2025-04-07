// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/TrustedSignerRegistry.sol";
import "../contracts/TrustedSignerNode.sol";
import "../contracts/interfaces/external/IExternalNode.sol";

/**
 * @title BinanceFundingRateTest
 * @notice Tests that the TrustedSignerNode can correctly process Binance funding rate data
 */
contract BinanceFundingRateTest is Test {
    TrustedSignerRegistry public registry;
    TrustedSignerNode public node;
    
    // Test accounts
    address authorizedSigner;
    uint256 signerPrivateKey;
    
    // Test data
    string symbol = "BTCUSDT";
    int256 fundingRate = 0.0001 * 1e18; // 0.01% scaled to 18 decimals

    function setUp() public {
        // Generate a private key and address for the authorized signer
        signerPrivateKey = 0xBEEF; // For testing only, use a deterministic key
        authorizedSigner = vm.addr(signerPrivateKey);
        
        // Deploy the registry and authorize the signer
        registry = new TrustedSignerRegistry();
        registry.authorizeSigner(authorizedSigner);
        
        // Deploy the node with the registry
        node = new TrustedSignerNode(address(registry));
    }
    
    function testProcessFundingRateData() public {
        // Generate the current timestamp
        uint256 timestamp = block.timestamp;
        
        // Create the message hash that would be signed
        bytes32 messageHash = keccak256(abi.encodePacked(symbol, fundingRate, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Sign the message with the authorized signer's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode the price data
        bytes memory priceData = abi.encode(fundingRate, timestamp);
        
        // Combine into the complete signed data
        bytes memory signedData = bytes.concat(priceData, signature);
        
        // Encode the parameters for the node
        bytes memory parameters = abi.encode(symbol, signedData);
        
        // Process the funding rate data through the node
        NodeOutput.Data memory output = node.process(
            new NodeOutput.Data[](0),
            parameters,
            new bytes32[](0),
            new bytes32[](0)
        );
        
        // Verify the output is correct
        assertEq(output.price, fundingRate, "Funding rate does not match");
        assertEq(output.timestamp, timestamp, "Timestamp does not match");
    }
    
    function testRejectsStaleData() public {
        // Set the current time to a specific value
        uint256 currentTime = 1000000;
        vm.warp(currentTime);
        
        // Generate a timestamp that is 10 minutes old (exceeds freshness window)
        uint256 timestamp = currentTime - 10 minutes;
        
        // Create the message hash that would be signed
        bytes32 messageHash = keccak256(abi.encodePacked(symbol, fundingRate, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Sign the message with the authorized signer's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode the price data
        bytes memory priceData = abi.encode(fundingRate, timestamp);
        
        // Combine into the complete signed data
        bytes memory signedData = bytes.concat(priceData, signature);
        
        // Encode the parameters for the node
        bytes memory parameters = abi.encode(symbol, signedData);
        
        // Expect the transaction to revert due to stale data
        vm.expectRevert("TrustedSignerNode: price data too old");
        node.process(
            new NodeOutput.Data[](0),
            parameters,
            new bytes32[](0),
            new bytes32[](0)
        );
    }
    
    function testRejectsUnauthorizedSigner() public {
        // Generate a different private key for an unauthorized signer
        uint256 unauthorizedPrivateKey = 0xCAFE; // Different from the authorized key
        
        // Generate the current timestamp
        uint256 timestamp = block.timestamp;
        
        // Create the message hash that would be signed
        bytes32 messageHash = keccak256(abi.encodePacked(symbol, fundingRate, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Sign the message with the unauthorized signer's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unauthorizedPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode the price data
        bytes memory priceData = abi.encode(fundingRate, timestamp);
        
        // Combine into the complete signed data
        bytes memory signedData = bytes.concat(priceData, signature);
        
        // Encode the parameters for the node
        bytes memory parameters = abi.encode(symbol, signedData);
        
        // Expect the transaction to revert due to unauthorized signer
        vm.expectRevert("TrustedSignerNode: signer not authorized");
        node.process(
            new NodeOutput.Data[](0),
            parameters,
            new bytes32[](0),
            new bytes32[](0)
        );
    }
} 