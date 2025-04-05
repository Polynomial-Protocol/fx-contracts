// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../storage/NodeDefinition.sol";
import "../storage/NodeOutput.sol";

library SimpleTrustedSignerNode {
    using ECDSA for bytes32;

    struct PriceData {
        bytes32 assetId;
        int256 price;
        uint256 timestamp;
        bytes signature;
    }

    function process(
        bytes memory parameters,
        bytes32[] memory runtimeKeys,
        bytes32[] memory runtimeValues
    ) internal view returns (NodeOutput.Data memory nodeOutput, bytes memory possibleError) {
        // Decode parameters - address of trusted signer, asset ID, and max staleness
        (address trustedSigner, bytes32 assetId, uint256 maxStaleness) = abi.decode(
            parameters, 
            (address, bytes32, uint256)
        );
        
        // Find price data in runtime parameters
        if (runtimeKeys.length == 0 || runtimeValues.length == 0) {
            possibleError = bytes("No runtime parameters provided");
            return (nodeOutput, possibleError);
        }

        // Look for our asset ID in the runtime data
        PriceData memory priceData;
        bool foundAsset = false;
        
        for (uint i = 0; i < runtimeValues.length; i++) {
            PriceData memory currentData = abi.decode(abi.encode(runtimeValues[i]), (PriceData));
            if (currentData.assetId == assetId) {
                priceData = currentData;
                foundAsset = true;
                break;
            }
        }
        
        if (!foundAsset) {
            possibleError = bytes("Asset not found in runtime data");
            return (nodeOutput, possibleError);
        }
        
        // Verify timestamp staleness
        if (priceData.timestamp + maxStaleness < block.timestamp) {
            possibleError = bytes("Price data is stale");
            return (nodeOutput, possibleError);
        }
        
        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            priceData.assetId,
            priceData.price, 
            priceData.timestamp
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recoveredSigner = ethSignedMessageHash.recover(priceData.signature);
        
        if (recoveredSigner != trustedSigner) {
            possibleError = bytes("Invalid signature");
            return (nodeOutput, possibleError);
        }
        
        // Return the verified price
        nodeOutput = NodeOutput.Data(priceData.price, priceData.timestamp, 0, 0);
        possibleError = new bytes(0);
    }

    function isValid(NodeDefinition.Data memory nodeDefinition) internal pure returns (bool) {
        // Must have no parents
        if (nodeDefinition.parents.length > 0) {
            return false;
        }

        // Must have correct parameter format
        if (nodeDefinition.parameters.length < 96) { // address + bytes32 + uint256
            return false;
        }

        (address trustedSigner, bytes32 assetId, ) = abi.decode(
            nodeDefinition.parameters, 
            (address, bytes32, uint256)
        );
        
        // Signer cannot be zero address
        if (trustedSigner == address(0)) {
            return false;
        }
        
        // Asset ID cannot be empty
        if (assetId == bytes32(0)) {
            return false;
        }

        return true;
    }
} 