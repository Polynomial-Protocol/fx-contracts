// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TrustedSignerRegistry
 * @notice Contract to manage the list of authorized signers for the oracle system
 */
contract TrustedSignerRegistry is Ownable {
    // Mapping of signer address to authorization status
    mapping(address => bool) public authorizedSigners;
    
    // Events
    event SignerAuthorized(address indexed signer);
    event SignerRevoked(address indexed signer);
    
    /**
     * @notice Constructor initializes the contract with the deployer as owner
     */
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Add a signer to the authorized list
     * @param signer Address of the signer to authorize
     */
    function authorizeSigner(address signer) external onlyOwner {
        require(signer != address(0), "Cannot authorize zero address");
        require(!authorizedSigners[signer], "Signer already authorized");
        
        authorizedSigners[signer] = true;
        emit SignerAuthorized(signer);
    }
    
    /**
     * @notice Remove a signer from the authorized list
     * @param signer Address of the signer to revoke
     */
    function revokeSigner(address signer) external onlyOwner {
        require(authorizedSigners[signer], "Signer not authorized");
        
        authorizedSigners[signer] = false;
        emit SignerRevoked(signer);
    }
    
    /**
     * @notice Check if a signer is authorized
     * @param signer Address of the signer to check
     * @return status True if the signer is authorized
     */
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return authorizedSigners[signer];
    }
} 