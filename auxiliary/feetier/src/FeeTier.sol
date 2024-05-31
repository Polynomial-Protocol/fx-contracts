//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IFeeTier, OrderFee} from "./interfaces/IFeeTier.sol";



contract FeeTierImpl is IFeeTier {

    // marketId => accountId => fee
    mapping(uint128 => mapping(uint128 => OrderFee.Data)) private _feeTiers;

    function getFees(uint128 accountId, uint128 marketId) public view returns (OrderFee.Data memory) {
        return _feeTiers[marketId][accountId];
    }

    // FIXME: implement setFees
    function setFees(uint128 accountId, uint128 marketId, OrderFee.Data memory fee) public {
        _feeTiers[marketId][accountId] = fee;
    }
}
