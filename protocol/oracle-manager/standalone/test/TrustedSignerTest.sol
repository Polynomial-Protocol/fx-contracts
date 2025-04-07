// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/TrustedSignerRegistry.sol";
import "../contracts/TrustedSignerNode.sol";

contract TrustedSignerTest is Test {
    TrustedSignerRegistry public registry;
    TrustedSignerNode public node;
    
    address public owner = address(0x1);
    address public signer = address(0x2);
    address public randomUser = address(0x3);
    
    function setUp() public {
        vm.startPrank(owner);
        registry = new TrustedSignerRegistry();
        node = new TrustedSignerNode(address(registry));
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