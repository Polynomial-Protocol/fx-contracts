// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";

/**
 * @title SignerUtils
 * @notice Utility library for signing oracle data
 */
library SignerUtils {
    /**
     * @notice Creates a signed price update for the trusted signer oracle
     * @param assetId The asset identifier (e.g., "ETH")
     * @param price The price value
     * @param timestamp The timestamp of the price
     * @param signerPrivateKey The private key of the authorized signer
     * @return The encoded price data with signature
     */
    function createSignedPriceUpdate(
        string memory assetId,
        int256 price,
        uint256 timestamp,
        uint256 signerPrivateKey
    ) internal pure returns (bytes memory) {
        // Step 1: Create the message hash
        bytes32 messageHash = keccak256(abi.encodePacked(assetId, price, timestamp));
        
        // Step 2: Create the Ethereum signed message hash (EIP-191)
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Step 3: Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedMessageHash);
        
        // Step 4: Encode the signature
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Step 5: Encode the price data
        bytes memory priceData = abi.encode(price, timestamp);
        
        // Step 6: Concatenate the data and signature
        return bytes.concat(priceData, signature);
    }
    
    /**
     * @notice Derives address from private key
     * @param privateKey The private key
     * @return The corresponding address
     */
    function getAddressFromPrivateKey(uint256 privateKey) internal pure returns (address) {
        return vm.addr(privateKey);
    }
    
    /**
     * @notice Creates node parameters for a price update
     * @param assetId The asset identifier
     * @param signedData The signed price data
     * @return Encoded parameters for the trusted signer node
     */
    function createNodeParameters(
        string memory assetId,
        bytes memory signedData
    ) internal pure returns (bytes memory) {
        return abi.encode(assetId, signedData);
    }
} 