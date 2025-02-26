//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {OffchainOrder} from "../storage/OffchainOrder.sol";
import {LimitOrder} from "../storage/LimitOrder.sol";

interface IOffchainLimitOrderModule {
    function settleOffchainLimitOrder(
        OffchainOrder.Data memory firstOrder,
        OffchainOrder.Signature memory firstSignature,
        OffchainOrder.Data memory secondOrder,
        OffchainOrder.Signature memory secondSignature
    ) external;

    /**
     * @notice cancels a limit order, can only be called by an account with the permission to cancel
     * @param accountId limit order account id
     * @param nonce limit order nonce
     */
    function cancelOffchainLimitOrder(uint128 accountId, uint256 nonce) external;

    function cancelOffchainLimitOrder(
        LimitOrder.CancelOrderRequest memory request,
        LimitOrder.Signature calldata sig
    ) external;

    event LimitOrderCancelled(uint128 indexed accountId, uint256 limitOrderNonce);

    error LimitOrderAlreadyUsed(uint128 accountId, uint256 limitOrderNonce);
}
