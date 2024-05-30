//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {OrderFee} from "../storage/OrderFee.sol";

interface IFeeTier {
    function getFees(uint128 accountId, uint128 marketId) external returns (OrderFee.Data memory);
}
