// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title PriceDataSigner
 * @notice Helper contract to generate and verify signatures for price data
 * @dev This contract is for testing purposes only
 */
contract PriceDataSigner {
    using ECDSA for bytes32;
    
    /**
     * @notice Creates a signature for price data
     * @param assetId The unique identifier for the asset
     * @param price The price of the asset (18 decimals)
     * @param timestamp The timestamp when the price was recorded
     * @param privateKey The private key of the signer (for testing only)
     * @return signature The complete signature package containing data and signature
     */
    function signPriceData(
        string memory assetId, 
        int256 price, 
        uint256 timestamp,
        uint256 privateKey
    ) external pure returns (bytes memory) {
        // Encode the price data (this will be part of the complete signature)
        bytes memory encodedData = abi.encode(price, timestamp);
        
        // Create message hash
        bytes32 messageHash = keccak256(abi.encodePacked(assetId, price, timestamp));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm_sign(privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Combine the data and signature into a complete signature package
        return bytes.concat(encodedData, signature);
    }
    
    /**
     * @notice Verify a signature for price data
     * @param assetId The unique identifier for the asset
     * @param signature The complete signature package containing data and signature
     * @param expectedSigner The address that should have signed the data
     * @return isValid True if the signature is valid and from the expected signer
     * @return price The decoded price
     * @return timestamp The decoded timestamp
     */
    function verifySignature(
        string memory assetId, 
        bytes memory signature,
        address expectedSigner
    ) external pure returns (bool isValid, int256 price, uint256 timestamp) {
        // Extract the price data from the signature
        bytes memory encodedData = new bytes(signature.length - 65);
        for (uint i = 0; i < encodedData.length; i++) {
            encodedData[i] = signature[i];
        }
        
        // Decode the price data
        (price, timestamp) = abi.decode(encodedData, (int256, uint256));
        
        // Construct the message that was signed
        bytes32 messageHash = keccak256(abi.encodePacked(assetId, price, timestamp));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Extract the actual signature (r, s, v)
        bytes memory actualSignature = new bytes(65);
        for (uint i = 0; i < 65; i++) {
            actualSignature[i] = signature[encodedData.length + i];
        }
        
        // Recover the signer
        address recoveredSigner = ethSignedMessageHash.recover(actualSignature);
        
        // Check if the recovered signer matches the expected signer
        isValid = (recoveredSigner == expectedSigner);
    }
    
    /**
     * @notice Helper function to simulate signing a message
     * @dev This is a mock function for testing and not secure for production
     */
    function vm_sign(uint256 privateKey, bytes32 digest) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        // Simple example for testing - in real implementation this would use a proper ECDSA library
        // This is just a placeholder as private key operations should not be done on-chain
        // The actual signing would happen off-chain
        
        // For demo purposes only - this is not a working implementation
        r = bytes32(uint256(keccak256(abi.encodePacked(privateKey, digest, uint256(1)))));
        s = bytes32(uint256(keccak256(abi.encodePacked(privateKey, digest, uint256(2)))));
        v = uint8(27 + uint256(keccak256(abi.encodePacked(privateKey, digest, uint256(3)))) % 2);
        
        return (v, r, s);
    }
} 