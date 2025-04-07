// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/TrustedSignerRegistry.sol";
import "../contracts/TrustedSignerNode.sol";
import "../contracts/storage/NodeOutput.sol";

contract TrustedSignerSigningTest is Test {
    TrustedSignerRegistry public registry;
    TrustedSignerNode public node;
    
    address public owner = address(0x1);
    uint256 public signerPrivateKey = 0x2;
    address public signer;
    
    // Test data
    string constant ASSET_ID = "ETH";
    int256 constant PRICE = 3500 ether;
    
    function setUp() public {
        // Calculate signer address from private key
        signer = vm.addr(signerPrivateKey);
        
        vm.startPrank(owner);
        registry = new TrustedSignerRegistry();
        node = new TrustedSignerNode(address(registry));
        registry.authorizeSigner(signer);
        vm.stopPrank();
    }
    
    function testSignAndProcess() public {
        // 1. Generate a timestamp
        uint256 timestamp = block.timestamp;
        
        // 2. Create the message hash
        bytes32 messageHash = keccak256(abi.encodePacked(ASSET_ID, PRICE, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // 3. Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 4. Encode the price data
        bytes memory priceData = abi.encode(PRICE, timestamp);
        
        // 5. Combine into the complete signed data
        bytes memory signedData = bytes.concat(priceData, signature);
        
        // 6. Create the parameters for the node
        bytes memory parameters = abi.encode(ASSET_ID, signedData);
        
        // 7. Create empty arrays for the parent outputs and runtime data
        NodeOutput.Data[] memory parentNodeOutputs = new NodeOutput.Data[](0);
        bytes32[] memory runtimeKeys = new bytes32[](0);
        bytes32[] memory runtimeValues = new bytes32[](0);
        
        // 8. Process the node
        NodeOutput.Data memory output = node.process(
            parentNodeOutputs,
            parameters,
            runtimeKeys,
            runtimeValues
        );
        
        // 9. Verify the output
        assertEq(output.price, PRICE, "Price mismatch");
        assertEq(output.timestamp, timestamp, "Timestamp mismatch");
    }
    
    function testStalePrice() public {
        // 1. Set current timestamp
        uint256 currentTime = 1000000;
        vm.warp(currentTime);
        
        // 2. Generate a timestamp in the past (outside the freshness window)
        uint256 timestamp = currentTime - 6 minutes;
        
        // 3. Create the message hash
        bytes32 messageHash = keccak256(abi.encodePacked(ASSET_ID, PRICE, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // 4. Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 5. Encode the price data
        bytes memory priceData = abi.encode(PRICE, timestamp);
        
        // 6. Combine into the complete signed data
        bytes memory signedData = bytes.concat(priceData, signature);
        
        // 7. Create the parameters for the node
        bytes memory parameters = abi.encode(ASSET_ID, signedData);
        
        // 8. Create empty arrays for the parent outputs and runtime data
        NodeOutput.Data[] memory parentNodeOutputs = new NodeOutput.Data[](0);
        bytes32[] memory runtimeKeys = new bytes32[](0);
        bytes32[] memory runtimeValues = new bytes32[](0);
        
        // 9. Process should revert due to stale price
        vm.expectRevert("TrustedSignerNode: price data too old");
        node.process(
            parentNodeOutputs,
            parameters,
            runtimeKeys,
            runtimeValues
        );
    }
    
    function testUnauthorizedSigner() public {
        // 1. Use a different private key (unauthorized)
        uint256 unauthorizedPrivateKey = 0x3;
        
        // 2. Generate a timestamp
        uint256 timestamp = block.timestamp;
        
        // 3. Create the message hash
        bytes32 messageHash = keccak256(abi.encodePacked(ASSET_ID, PRICE, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // 4. Sign the message with unauthorized key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unauthorizedPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 5. Encode the price data
        bytes memory priceData = abi.encode(PRICE, timestamp);
        
        // 6. Combine into the complete signed data
        bytes memory signedData = bytes.concat(priceData, signature);
        
        // 7. Create the parameters for the node
        bytes memory parameters = abi.encode(ASSET_ID, signedData);
        
        // 8. Create empty arrays for the parent outputs and runtime data
        NodeOutput.Data[] memory parentNodeOutputs = new NodeOutput.Data[](0);
        bytes32[] memory runtimeKeys = new bytes32[](0);
        bytes32[] memory runtimeValues = new bytes32[](0);
        
        // 9. Process should revert due to unauthorized signer
        vm.expectRevert("TrustedSignerNode: signer not authorized");
        node.process(
            parentNodeOutputs,
            parameters,
            runtimeKeys,
            runtimeValues
        );
    }
} 