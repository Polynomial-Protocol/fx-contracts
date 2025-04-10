//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

library OffchainOrder {
    error ReduceOnlyOrder(int128 currentSize, int128 sizeDelta);

    struct TpSlSettings {
        uint256 tpPriceA;
        uint256 tpPriceB;
        uint256 slPriceA;
        uint256 slPriceB;
    }

    struct Data {
        /**
         * @dev marketId
         */
        uint128 marketId;
        /**
         * @dev accountId
         */
        uint128 accountId;
        /**
         * @dev sizeDelta for AsyncOrder, amount for LimitOrder
         */
        int128 sizeDelta;
        /**
         * @dev settlementStrategyId
         */
        uint128 settlementStrategyId;
        /**
         * @dev referrerOrRelayer for AsyncOrder, relayer for LimitOrder
         */
        address referrerOrRelayer;
        /**
         * @dev Is the account a maker?
         */
        bool limitOrderMaker;
        /**
         * @dev Allow aggregation of AsyncOrder and LimitOrder
         */
        bool allowAggregation;
        /**
         * @dev Allow partial matching of LimitOrder
         */
        bool allowPartialMatching;
        /**
         * @dev Is the order reduce only?
         */
        bool reduceOnly;
        /**
         * @dev timestamp of signing
         */
        uint64 timestamp;
        /**
         * @dev acceptablePrice for AsyncOrder, price for LimitOrder
         */
        uint256 acceptablePrice;
        /**
         * @dev tracking code
         */
        bytes32 trackingCode;
        /**
         * @dev expiration
         */
        uint256 expiration;
        /**
         * @dev nonce
         */
        uint256 nonce;
    }

    struct NonceData {
        /**
         * @dev nonceBitmaps is a mapping of account ids to their current order nonces
         */
        mapping(uint128 => mapping(uint256 => uint256)) nonceBitmaps;
    }

    function load() internal pure returns (NonceData storage offchainOrderNonces) {
        bytes32 s = keccak256(abi.encode("io.synthetix.perps-market.OffchainOrder"));
        assembly {
            offchainOrderNonces.slot := s
        }
    }

    /**
     * @notice Offchain Order signature struct.
     */
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @dev Checks if a order nonce has been used by a given account.
     * @param self The Data storage struct.
     * @param accountId The account ID to check.
     * @param nonce The order nonce to check.
     * @return bool true if the nonce has been used, false otherwise.
     */
    function isOffchainOrderNonceUsed(
        NonceData storage self,
        uint128 accountId,
        uint256 nonce
    ) internal view returns (bool) {
        uint256 slot = nonce / 256; // Determine the bitmap slot
        uint256 bit = nonce % 256; // Determine the bit position within the slot
        return (self.nonceBitmaps[accountId][slot] & (1 << bit)) != 0;
    }

    /**
     * @dev Marks a order nonce as used for a given account.
     * @param self The Data storage struct.
     * @param accountId The account ID to mark the nonce for.
     * @param nonce The nonce to mark as used.
     */
    function markOffchainOrderNonceUsed(
        NonceData storage self,
        uint128 accountId,
        uint256 nonce
    ) internal {
        uint256 slot = nonce / 256;
        uint256 bit = nonce % 256;
        self.nonceBitmaps[accountId][slot] |= 1 << bit;
    }
}
