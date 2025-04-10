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

    /**
     * @notice Offchain Order signature struct.
     */
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
}
