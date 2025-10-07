//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {DecimalMath} from "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";

library MarketClose {
    using DecimalMath for uint256;

    struct Data {
        bool isClosed;
        uint256 openTime;
        uint256 closeTime;
        uint256 closePrice;
        uint256 rolloverFee;
    }

    function load(uint128 marketId) internal pure returns (Data storage market) {
        bytes32 s = keccak256(abi.encode("fi.polynomial.perps-market.MarketClose", marketId));

        assembly {
            market.slot := s
        }
    }
}
