// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TrustedSignerRegistry
 * @notice Registry to manage authorized signers for the TrustedSignerNode
 */
contract TrustedSignerRegistry is Ownable {
    // Mapping of authorized signers
    mapping(address => bool) private _authorizedSigners;
    
    // Events
    event SignerAuthorized(address indexed signer);
    event SignerRevoked(address indexed signer);

    /**
     * @notice Checks if an address is authorized as a signer
     * @param signer Address to check
     * @return True if the address is an authorized signer
     */
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return _authorizedSigners[signer];
    }

    /**
     * @notice Authorizes an address as a trusted signer
     * @param signer Address to authorize
     */
    function authorizeSigner(address signer) external onlyOwner {
        require(signer != address(0), "TrustedSignerRegistry: zero address");
        require(!_authorizedSigners[signer], "TrustedSignerRegistry: already authorized");
        
        _authorizedSigners[signer] = true;
        emit SignerAuthorized(signer);
    }

    /**
     * @notice Revokes an address as a trusted signer
     * @param signer Address to revoke
     */
    function revokeSigner(address signer) external onlyOwner {
        require(_authorizedSigners[signer], "TrustedSignerRegistry: not authorized");
        
        _authorizedSigners[signer] = false;
        emit SignerRevoked(signer);
    }
} 