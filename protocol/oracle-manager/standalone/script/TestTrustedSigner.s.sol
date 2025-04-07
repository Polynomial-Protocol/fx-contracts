// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {NodeOutput} from "../contracts/storage/NodeOutput.sol";
import {TrustedSignerNode} from "../contracts/nodes/external-nodes/TrustedSignerNode.sol";
import {TrustedSignerRegistry} from "../contracts/nodes/external-nodes/TrustedSignerRegistry.sol";
import {PriceDataSigner} from "../contracts/nodes/external-nodes/PriceDataSigner.sol";

contract TestTrustedSigner is Script {
    // Set your deployed contract addresses here
    address public trustedSignerRegistry = 0x75283Ce4eb1aC5C5c8bc49b16Ed58AD545c0ce1C;
    address public trustedSignerNode = 0x5602ae80b8b692D24a4332B2E7beeFe3465109d9;
    
    // Use the private key from .env
    uint256 signerPrivateKey = vm.envUint("PRIVATE_KEY");
    
    function run() external {
        // Create a PriceDataSigner instance
        PriceDataSigner signer = new PriceDataSigner();
        
        // Set current price and timestamp
        uint256 price = 2000 * 1e18; // $2000.00 with 18 decimals
        uint256 timestamp = block.timestamp;
        
        console.log("Signing price data:");
        console.log("Price: %s", price / 1e18);
        console.log("Timestamp: %s", timestamp);
        
        // Sign the price data
        bytes32 messageHash = signer.getPriceMessageHash(price, timestamp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Prepare parameters for the node
        bytes memory priceData = abi.encode(price, timestamp);
        bytes memory signedData = abi.encode(priceData, signature);
        
        bytes memory parameters = abi.encode(signedData);
        
        // Simulate a call to process the price data
        vm.startBroadcast();
        try TrustedSignerNode(trustedSignerNode).process(new NodeOutput.Data[](0), parameters, new bytes32[](0), new bytes[](0)) returns (NodeOutput.Data memory output) {
            console.log("Price processed successfully!");
            console.log("Output price: %s", uint256(output.price) / 1e18);
            console.log("Output timestamp: %s", output.timestamp);
        } catch Error(string memory reason) {
            console.log("Error processing price: %s", reason);
        }
        vm.stopBroadcast();
    }
}
