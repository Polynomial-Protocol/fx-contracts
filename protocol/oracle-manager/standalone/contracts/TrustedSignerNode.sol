// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "./TrustedSignerRegistry.sol";
import "./storage/NodeOutput.sol";
import "./storage/NodeDefinition.sol";
import "./interfaces/external/IExternalNode.sol";

/**
 * @title TrustedSignerNode
 * @notice A node that verifies signed price data from trusted signers
 */
contract TrustedSignerNode is IExternalNode {
    using ECDSA for bytes32;

    // Registry of trusted signers
    TrustedSignerRegistry public immutable registry;

    // Time window in seconds that a price is considered fresh
    uint256 public constant FRESHNESS_WINDOW = 5 minutes;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor to set trusted signers registry
     * @param _registry Address of the TrustedSignerRegistry contract
     */
    constructor(address _registry) {
        registry = TrustedSignerRegistry(_registry);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL NODE INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IExternalNode
     */
    function process(
        NodeOutput.Data[] memory,
        bytes memory parameters,
        bytes32[] memory,
        bytes32[] memory
    ) external view returns (NodeOutput.Data memory) {
        // Decode parameters
        (string memory assetId, bytes memory signedData) = abi.decode(parameters, (string, bytes));

        // Extract price data and signature from the signedData
        (int256 price, uint256 timestamp, address signer) = _extractSignedData(assetId, signedData);

        // Verify the signer is authorized
        require(registry.isAuthorizedSigner(signer), "TrustedSignerNode: signer not authorized");

        // Verify timestamp is not too old
        require(
            block.timestamp - timestamp <= FRESHNESS_WINDOW,
            "TrustedSignerNode: price data too old"
        );

        // Return the price data
        return NodeOutput.Data({price: price, timestamp: timestamp, __unused1: 0, __unused2: 0});
    }

    /**
     * @inheritdoc IExternalNode
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IExternalNode).interfaceId ||
            interfaceId == 0x01ffc9a7; // ERC165 Interface ID
    }

    /**
     * @inheritdoc IExternalNode
     */
    function validateParameters(bytes memory parameters) external pure returns (bool) {
        // Make sure parameters are properly encoded
        (string memory assetId, bytes memory signedData) = abi.decode(parameters, (string, bytes));
        
        // Basic validation for non-empty parameters
        return 
            bytes(assetId).length > 0 && 
            signedData.length >= 96; // At minimum we need price (32 bytes) + timestamp (32 bytes) + signature (>= 32 bytes)
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Extracts and verifies signed price data
     * @param assetId The asset identifier
     * @param signedData The encoded data containing price, timestamp and signature
     * @return price The price from the signed data
     * @return timestamp The timestamp from the signed data
     * @return signer The recovered signer address
     */
    function _extractSignedData(string memory assetId, bytes memory signedData)
        internal
        pure
        returns (int256 price, uint256 timestamp, address signer)
    {
        // First, extract the price data and signature
        // The format is: abi.encode(price, timestamp) + signature
        // First 64 bytes contain price and timestamp
        // Rest is the signature
        
        // Get the price data portion (first part of signedData)
        bytes memory priceData = new bytes(64); // 32 bytes for price + 32 bytes for timestamp
        for (uint i = 0; i < 64; i++) {
            priceData[i] = signedData[i];
        }
        
        // Decode price and timestamp
        (price, timestamp) = abi.decode(priceData, (int256, uint256));
        
        // Extract signature (remaining bytes after price data)
        bytes memory signature = new bytes(signedData.length - 64);
        for (uint i = 0; i < signedData.length - 64; i++) {
            signature[i] = signedData[i + 64];
        }
        
        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(assetId, price, timestamp));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Recover signer
        signer = ethSignedMessageHash.recover(signature);
    }
} 