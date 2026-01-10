//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

library ProfitShare {
    bytes32 private constant _SLOT_PROFIT_SHARE =
        keccak256(abi.encode("fi.polynomial.strategy-market.ProfitShare"));

    struct Data {
        /**
         * @dev the address of the dev
         */
        address devAddress;
        /**
         * @dev the share of the profit to the dev
         */
        uint256 devShareD18;
    }

    function load() internal pure returns (Data storage profitShare) {
        bytes32 s = _SLOT_PROFIT_SHARE;
        assembly {
            profitShare.slot := s
        }
    }
}
