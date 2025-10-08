//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {OffchainOrder} from "../../storage/OffchainOrder.sol";
import {LimitOrder} from "../../storage/LimitOrder.sol";

interface IOffchainLimitOrderPythLazerModule {
    function settleOffchainLimitOrderPythLazer(
        OffchainOrder.Data memory firstOrder,
        OffchainOrder.Signature memory firstSignature,
        OffchainOrder.Data memory secondOrder,
        OffchainOrder.Signature memory secondSignature
    ) external;

    event LimitOrderCancelled(uint128 indexed accountId, uint256 limitOrderNonce);

    error LimitOrderAlreadyUsed(uint128 accountId, uint256 limitOrderNonce);
}
