// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

import "../../storage/NodeOutput.sol";
import "../../storage/NodeDefinition.sol";
import "../../interfaces/external/IExternalNode.sol";
import "./TrustedSignerRegistry.sol";

/**
 * @title TrustedSignerNode
 * @notice External node implementation for trusted signers to provide price feed data
 * @dev Implements IExternalNode interface for integration with Oracle Manager
 */
contract TrustedSignerNode is IExternalNode {
    using ECDSA for bytes32;

    // Trusted signer registry contract reference
    TrustedSignerRegistry public immutable registry;
    
    // Freshness threshold in seconds
    uint256 public constant FRESHNESS_THRESHOLD = 5 minutes;

    // Struct to represent signed price data
    struct SignedPrice {
        string assetId;     // Unique identifier for the asset
        int256 price;       // Price with 18 decimals
        uint256 timestamp;  // Unix timestamp when price was signed
    }

    // Error messages
    error InvalidSigner(address signer);
    error StalePrice(uint256 priceTimestamp, uint256 currentTimestamp);
    error InvalidParameters();
    error InvalidSignature();

    /**
     * @notice Constructor sets the trusted signer registry
     * @param _registry Address of the TrustedSignerRegistry contract
     */
    constructor(address _registry) {
        require(_registry != address(0), "Registry cannot be zero address");
        registry = TrustedSignerRegistry(_registry);
    }

    /**
     * @inheritdoc IERC165
     *
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IExternalNode).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @inheritdoc IExternalNode
     * @dev Parameters are expected to be encoded as (string assetId, bytes signature)
     * where signature is the signed message containing assetId, price, and timestamp
     */
    function process(
        NodeOutput.Data[] memory parentNodeOutputs,
        bytes memory parameters,
        bytes32[] memory runtimeKeys,
        bytes32[] memory runtimeValues
    ) external view returns (NodeOutput.Data memory) {
        // Decode parameters
        (string memory assetId, bytes memory signature) = abi.decode(parameters, (string, bytes));
        
        if (bytes(assetId).length == 0 || signature.length == 0) {
            revert InvalidParameters();
        }

        // Recover signed price data and signer
        SignedPrice memory signedPrice;
        address signer;
        (signedPrice, signer) = recoverSignedPrice(assetId, signature);
        
        // Verify the signer is authorized
        if (!registry.isAuthorizedSigner(signer)) {
            revert InvalidSigner(signer);
        }
        
        // Check if price is fresh
        if (block.timestamp > signedPrice.timestamp + FRESHNESS_THRESHOLD) {
            revert StalePrice(signedPrice.timestamp, block.timestamp);
        }
        
        // Return the price data
        return NodeOutput.Data({
            price: signedPrice.price,
            timestamp: signedPrice.timestamp,
            __slotAvailableForFutureUse1: 0,
            __slotAvailableForFutureUse2: 0
        });
    }

    /**
     * @inheritdoc IExternalNode
     */
    function isValid(NodeDefinition.Data memory nodeDefinition) external view returns (bool) {
        // Check if we have the right number of parents (0)
        if (nodeDefinition.parents.length != 0) {
            return false;
        }
        
        // Ensure parameters are valid by attempting to decode them
        try this.validateParameters(nodeDefinition.parameters) returns (bool valid) {
            return valid;
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Helper function to validate parameters format
     * @param parameters Encoded parameters
     * @return valid True if parameters are valid
     */
    function validateParameters(bytes memory parameters) external pure returns (bool) {
        if (parameters.length < 64) {
            return false;
        }
        
        // Try to decode parameters
        try abi.decode(parameters, (string, bytes)) {
            return true;
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Recovers the signed price data and the signer from a signature
     * @param assetId Asset identifier that was signed
     * @param signature ECDSA signature
     * @return signedPrice The recovered price data
     * @return signer The address that signed the data
     */
    function recoverSignedPrice(string memory assetId, bytes memory signature) 
        public pure 
        returns (SignedPrice memory signedPrice, address signer) 
    {
        // Extract the price data from the signature
        bytes memory encodedData = new bytes(signature.length - 65);
        for (uint i = 0; i < encodedData.length; i++) {
            encodedData[i] = signature[i];
        }
        
        // Decode the price data
        (int256 price, uint256 timestamp) = abi.decode(encodedData, (int256, uint256));
        
        // Set the price data
        signedPrice = SignedPrice({
            assetId: assetId,
            price: price,
            timestamp: timestamp
        });
        
        // Construct the message that was signed
        bytes32 messageHash = keccak256(abi.encodePacked(assetId, price, timestamp));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Extract the actual signature (r, s, v)
        bytes memory actualSignature = new bytes(65);
        for (uint i = 0; i < 65; i++) {
            actualSignature[i] = signature[encodedData.length + i];
        }
        
        // Recover the signer
        signer = ethSignedMessageHash.recover(actualSignature);
        
        if (signer == address(0)) {
            revert InvalidSignature();
        }
    }
} 