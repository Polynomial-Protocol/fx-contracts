//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

/**
 * @title Orders Fee data
 */
library LimitOrderFee {
    struct Data {
        /**
         * @dev Limit order maker fee. Applied when limit order is fully matched.
         */
        uint256 makerFee;
        /**
         * @dev Limit order taker fee. Applied when limit order is fully matched.
         */
        uint256 takerFee;
    }
}
