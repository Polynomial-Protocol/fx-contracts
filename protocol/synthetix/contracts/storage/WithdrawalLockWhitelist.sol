//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

/**
 * @title System wide whitelist for addresses that can set withdrawal locks.
 */
library WithdrawalLockWhitelist {
    bytes32 private constant _SLOT_WITHDRAWAL_LOCK_WHITELIST =
        keccak256(abi.encode("io.synthetix.synthetix.WithdrawalLockWhitelist"));

    struct Data {
        /**
         * @dev Mapping of addresses that are whitelisted to set withdrawal locks.
         */
        mapping(address => bool) whitelistedAddresses;
    }

    /**
     * @dev Returns the whitelist singleton.
     */
    function load() internal pure returns (Data storage whitelist) {
        bytes32 s = _SLOT_WITHDRAWAL_LOCK_WHITELIST;
        assembly {
            whitelist.slot := s
        }
    }
}
