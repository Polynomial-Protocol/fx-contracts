// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Test.sol";
import "../../contracts/nodes/external-nodes/TrustedSignerRegistry.sol";
import "../../contracts/nodes/external-nodes/TrustedSignerNode.sol";

/**
 * @title TrustedSignerNodeStandaloneTest
 * @notice Foundry tests for just the Trusted Signer Oracle components
 */
contract TrustedSignerNodeStandaloneTest is Test {
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
} 