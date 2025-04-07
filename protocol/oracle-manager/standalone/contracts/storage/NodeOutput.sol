// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

/**
 * @title NodeOutput
 * @notice Simple data structure to hold output data from nodes
 */
library NodeOutput {
    /**
     * @notice Structure to hold price output data
     */
    struct Data {
        // The price value with 18 decimals of precision
        int256 price;
        
        // The timestamp when this price was generated or observed
        uint256 timestamp;
        
        // Reserved fields for future use
        uint256 __unused1;
        uint256 __unused2;
    }
}
