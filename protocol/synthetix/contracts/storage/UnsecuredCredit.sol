//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";

library UnsecuredCredit {
    using SafeCastU128 for uint128;
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;

    struct MarketConfig {
        bool isWhitelisted;
        bool marketPaused;
        uint256 debtCapD18; // max unsecured debt per market; 0 means disabled
        uint256 ratePerSecondD18; // simple linear rate per second, 18d fixed-point
        uint256 epochLength; // seconds; optional throttle window
        uint256 epochLimitD18; // max borrow per epoch; 0 disables throttle
    }

    struct MarketState {
        uint256 principalD18;
        uint256 accruedInterestD18;
        uint256 badDebtD18;
        uint256 epochBorrowedD18;
        uint64 lastAccrual;
        uint64 lastEpoch;
    }

    struct Data {
        mapping(uint128 => MarketConfig) marketConfig;
        mapping(uint128 => MarketState) marketState;
        uint256 globalDebtCapD18; // 0 means disabled/unset; must be configured
        uint256 totalDebtD18;
        bool globalPaused;
    }

    function load() internal pure returns (Data storage data) {
        bytes32 slot = keccak256("io.synthetix.synthetix.UnsecuredCredit");
        assembly {
            data.slot := slot
        }
    }
}
