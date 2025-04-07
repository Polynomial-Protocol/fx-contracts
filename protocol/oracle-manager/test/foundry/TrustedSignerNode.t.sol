// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Test.sol";
import "../../contracts/nodes/external-nodes/TrustedSignerRegistry.sol";
import "../../contracts/nodes/external-nodes/TrustedSignerNode.sol";
import "../../contracts/storage/NodeOutput.sol";
import "../../contracts/storage/NodeDefinition.sol";

/**
 * @title TrustedSignerNodeTest
 * @notice Foundry tests for the Trusted Signer Oracle
 * @dev Run with:
 *      forge test --match-contract TrustedSignerNodeTest -vvv
 */
contract TrustedSignerNodeTest is Test {
    TrustedSignerRegistry public registry;
    TrustedSignerNode public node;
    
    address public owner = address(0x1);
    address public signer = address(0x2);
    address public randomUser = address(0x3);
    
    // Test data
    string constant ASSET_ID = "ETH";
    int256 constant PRICE = 3500 ether;
    
    function setUp() public {
        // Deploy contracts with owner
        vm.startPrank(owner);
        registry = new TrustedSignerRegistry();
        node = new TrustedSignerNode(address(registry));
        
        // Authorize the signer
        registry.authorizeSigner(signer);
        vm.stopPrank();
    }
    
    function testNodeSupportsInterface() public {
        // IExternalNode interface ID
        bytes4 externalNodeInterfaceId = 0x3c508a74;
        assertTrue(node.supportsInterface(externalNodeInterfaceId));
    }
    
    function testAuthorizeSigner() public {
        // Verify initial state
        assertTrue(registry.isAuthorizedSigner(signer));
        assertFalse(registry.isAuthorizedSigner(randomUser));
        
        // Test authorization
        vm.prank(owner);
        registry.authorizeSigner(randomUser);
        assertTrue(registry.isAuthorizedSigner(randomUser));
        
        // Test revocation
        vm.prank(owner);
        registry.revokeSigner(signer);
        assertFalse(registry.isAuthorizedSigner(signer));
    }
    
    function testAuthorizationFail() public {
        // Authorization should fail if not owner
        vm.prank(randomUser);
        vm.expectRevert();
        registry.authorizeSigner(randomUser);
    }
    
    function testParameterValidation() public {
        // Valid parameters
        bytes memory validParams = abi.encode(ASSET_ID, hex"1234567890");
        assertTrue(node.validateParameters(validParams));
        
        // Invalid parameters (too short)
        bytes memory invalidParams = hex"1234";
        vm.expectRevert();
        node.validateParameters(invalidParams);
    }
    
    function testPriceDataSigning() public {
        // Generate signed data
        uint256 timestamp = block.timestamp;
        bytes32 messageHash = keccak256(abi.encodePacked(ASSET_ID, PRICE, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Use a known private key for signer
        uint256 signerPrivateKey = 0x2;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode price data
        bytes memory encodedData = abi.encode(PRICE, timestamp);
        
        // Create complete signature
        bytes memory completeSignature = bytes.concat(encodedData, signature);
        
        // Create parent node outputs (empty for this test)
        NodeOutput.Data[] memory parentNodeOutputs = new NodeOutput.Data[](0);
        
        // Create parameters for the process function
        bytes memory parameters = abi.encode(ASSET_ID, completeSignature);
        
        // Test node processing
        NodeOutput.Data memory output = node.process(
            parentNodeOutputs,
            parameters,
            new bytes32[](0),
            new bytes32[](0)
        );
        
        // Verify output
        assertEq(output.price, PRICE);
        assertEq(output.timestamp, timestamp);
    }
    
    function testStalenessFail() public {
        // Generate signed data with a stale timestamp
        uint256 staleTimestamp = block.timestamp - 6 minutes; // 6 min ago (freshness is 5 min)
        bytes32 messageHash = keccak256(abi.encodePacked(ASSET_ID, PRICE, staleTimestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Use a known private key for signer
        uint256 signerPrivateKey = 0x2;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode price data
        bytes memory encodedData = abi.encode(PRICE, staleTimestamp);
        
        // Create complete signature
        bytes memory completeSignature = bytes.concat(encodedData, signature);
        
        // Create parent node outputs (empty for this test)
        NodeOutput.Data[] memory parentNodeOutputs = new NodeOutput.Data[](0);
        
        // Create parameters for the process function
        bytes memory parameters = abi.encode(ASSET_ID, completeSignature);
        
        // Expect revert due to staleness
        vm.expectRevert();
        node.process(
            parentNodeOutputs,
            parameters,
            new bytes32[](0),
            new bytes32[](0)
        );
    }
    
    function testUnauthorizedSignerFail() public {
        // Generate signed data from unauthorized signer
        uint256 timestamp = block.timestamp;
        bytes32 messageHash = keccak256(abi.encodePacked(ASSET_ID, PRICE, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Use a random private key (not authorized)
        uint256 randomPrivateKey = 0x999;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randomPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode price data
        bytes memory encodedData = abi.encode(PRICE, timestamp);
        
        // Create complete signature
        bytes memory completeSignature = bytes.concat(encodedData, signature);
        
        // Create parent node outputs (empty for this test)
        NodeOutput.Data[] memory parentNodeOutputs = new NodeOutput.Data[](0);
        
        // Create parameters for the process function
        bytes memory parameters = abi.encode(ASSET_ID, completeSignature);
        
        // Expect revert due to unauthorized signer
        vm.expectRevert();
        node.process(
            parentNodeOutputs,
            parameters,
            new bytes32[](0),
            new bytes32[](0)
        );
    }
} 