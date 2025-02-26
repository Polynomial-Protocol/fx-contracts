//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {ERC2771Context} from "@synthetixio/core-contracts/contracts/utils/ERC2771Context.sol";
import {FeatureFlag} from "@synthetixio/core-modules/contracts/storage/FeatureFlag.sol";
import {Account} from "@synthetixio/main/contracts/storage/Account.sol";
import {AccountRBAC} from "@synthetixio/main/contracts/storage/AccountRBAC.sol";
import {SafeCastU256, SafeCastI256} from "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import {DecimalMath} from "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";
import {OffchainOrder} from "../storage/OffchainOrder.sol";
import {GlobalPerpsMarket} from "../storage/GlobalPerpsMarket.sol";
import {PerpsPrice} from "../storage/PerpsPrice.sol";
import {PerpsMarket} from "../storage/PerpsMarket.sol";
import {LimitOrder} from "../storage/LimitOrder.sol";
import {AsyncOrder} from "../storage/AsyncOrder.sol";
import {PerpsAccount} from "../storage/PerpsAccount.sol";
import {GlobalPerpsMarketConfiguration} from "../storage/GlobalPerpsMarketConfiguration.sol";
import {PerpsMarketConfiguration} from "../storage/PerpsMarketConfiguration.sol";
import {Position} from "../storage/Position.sol";
import {SettlementStrategy} from "../storage/SettlementStrategy.sol";
import {MarketUpdate} from "../storage/MarketUpdate.sol";
import {PerpsMarketFactory} from "../storage/PerpsMarketFactory.sol";
import {KeeperCosts} from "../storage/KeeperCosts.sol";
import {IOffchainOrderModule} from "../interfaces/IOffchainOrderModule.sol";
import {ILimitOrderModule} from "../interfaces/ILimitOrderModule.sol";
import {IOffchainLimitOrderModule} from "../interfaces/IOffchainLimitOrderModule.sol";
import {IMarketEvents} from "../interfaces/IMarketEvents.sol";
import {IAccountEvents} from "../interfaces/IAccountEvents.sol";
import {IAsyncOrderSettlementPythModule} from "../interfaces/IAsyncOrderSettlementPythModule.sol";
import {IPythERC7412Wrapper} from "../interfaces/external/IPythERC7412Wrapper.sol";
import {Flags} from "../utils/Flags.sol";
import {MathUtil} from "../utils/MathUtil.sol";

contract OffchainLimitOrderModule is IOffchainLimitOrderModule, IMarketEvents, IAccountEvents {
    using SafeCastI256 for int256;
    using SafeCastU256 for uint256;
    using DecimalMath for int128;
    using DecimalMath for uint256;
    using GlobalPerpsMarket for GlobalPerpsMarket.Data;
    using PerpsMarket for PerpsMarket.Data;
    using LimitOrder for LimitOrder.Data;
    using AsyncOrder for AsyncOrder.Data;
    using PerpsAccount for PerpsAccount.Data;
    using GlobalPerpsMarketConfiguration for GlobalPerpsMarketConfiguration.Data;
    using PerpsMarketConfiguration for PerpsMarketConfiguration.Data;
    using Position for Position.Data;
    using PerpsMarketFactory for PerpsMarketFactory.Data;

    // keccak256("OffchainOrder(uint128 marketId,uint128 accountId,int128 sizeDelta,uint128 settlementStrategyId,address referrerOrRelayer,bool allowAggregation,bool allowPartialMatching,uint256 acceptablePrice,bytes32 trackingCode,uint256 expiration,uint256 nonce)");
    bytes32 private constant _ORDER_TYPEHASH =
        0xa116e0c85e44ab4eeb1d489620b69f76222f65de5606f5b5d381b7f1ecab0179;

    // keccak256("CancelOrderRequest(uint128 accountId,uint256 nonce)");
    bytes32 private constant _CANCEL_ORDER_TYPEHASH =
        0x19ed75f4cc40098870adbe5a13fc22a2033f4ed7d8e529e56631c022faf948d5;

    function cancelOffchainLimitOrder(uint128 accountId, uint256 nonce) external {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);
        FeatureFlag.ensureAccessToFeature(Flags.LIMIT_ORDER);

        Account.loadAccountAndValidatePermission(accountId, AccountRBAC._PERPS_CANCEL_LIMIT_ORDER);

        LimitOrder.Data storage limitOrderData = LimitOrder.load();

        if (limitOrderData.isLimitOrderNonceUsed(accountId, nonce)) {
            revert LimitOrderAlreadyUsed(accountId, nonce);
        } else {
            limitOrderData.markLimitOrderNonceUsed(accountId, nonce);
            emit LimitOrderCancelled(accountId, nonce);
        }
    }

    function cancelOffchainLimitOrder(
        LimitOrder.CancelOrderRequest calldata order,
        LimitOrder.Signature calldata sig
    ) external {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);
        FeatureFlag.ensureAccessToFeature(Flags.LIMIT_ORDER);
        checkCancelOrderSigPermission(order, sig);
        LimitOrder.Data storage limitOrderData = LimitOrder.load();

        if (limitOrderData.isLimitOrderNonceUsed(order.accountId, order.nonce)) {
            revert LimitOrderAlreadyUsed(order.accountId, order.nonce);
        } else {
            limitOrderData.markLimitOrderNonceUsed(order.accountId, order.nonce);
            emit LimitOrderCancelled(order.accountId, order.nonce);
        }
    }

    function settleOffchainLimitOrder(
        OffchainOrder.Data memory firstOrder,
        OffchainOrder.Signature memory firstSignature,
        OffchainOrder.Data memory secondOrder,
        OffchainOrder.Signature memory secondSignature
    ) external {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);
        FeatureFlag.ensureAccessToFeature(Flags.LIMIT_ORDER);
        PerpsMarket.loadValid(firstOrder.marketId);
        Account.exists(firstOrder.accountId);
        Account.exists(secondOrder.accountId);

        checkSigPermission(firstOrder, firstSignature);
        checkSigPermission(secondOrder, secondSignature);

        LimitOrder.LimitOrderPartialFillData memory partialFillData;

        uint256 lastPriceCheck = PerpsPrice.getCurrentPrice(
            firstOrder.marketId,
            PerpsPrice.Tolerance.DEFAULT
        );

        PerpsMarket.Data storage perpsMarketData = PerpsMarket.load(firstOrder.marketId);
        perpsMarketData.recomputeFunding(lastPriceCheck);

        PerpsMarketConfiguration.Data storage marketConfig = PerpsMarketConfiguration.load(
            firstOrder.marketId
        );

        (
            partialFillData.firstOrderPartialFill,
            partialFillData.secondOrderPartialFill
        ) = updateLimitOrderAmounts(firstOrder, secondOrder);

        perpsMarketData.validateLimitOrderSize(
            marketConfig.maxMarketSize,
            marketConfig.maxMarketValue,
            firstOrder.acceptablePrice,
            firstOrder.sizeDelta
        );

        validateLimitOrder(firstOrder);
        validateLimitOrder(secondOrder);
        validateLimitOrderPair(firstOrder, secondOrder);

        uint256 shareRatioD18 = GlobalPerpsMarketConfiguration.load().relayerShare[
            firstOrder.referrerOrRelayer
        ];
        if (shareRatioD18 == 0) {
            revert ILimitOrderModule.LimitOrderRelayerInvalid(firstOrder.referrerOrRelayer);
        }

        (
            uint256 firstLimitOrderFees,
            Position.Data storage firstOldPosition,
            Position.Data memory firstNewPosition
        ) = validateLimitOrderRequest(firstOrder, lastPriceCheck, marketConfig, perpsMarketData);
        (
            uint256 secondLimitOrderFees,
            Position.Data storage secondOldPosition,
            Position.Data memory secondNewPosition
        ) = validateLimitOrderRequest(secondOrder, lastPriceCheck, marketConfig, perpsMarketData);

        settleLimitOrder(
            firstOrder,
            firstLimitOrderFees,
            firstOldPosition,
            firstNewPosition,
            partialFillData.firstOrderPartialFill
        );
        settleLimitOrder(
            secondOrder,
            secondLimitOrderFees,
            secondOldPosition,
            secondNewPosition,
            partialFillData.secondOrderPartialFill
        );
    }

    function updateLimitOrderAmounts(
        OffchainOrder.Data memory firstOrder,
        OffchainOrder.Data memory secondOrder
    ) internal returns (bool firstOrderPartialFill, bool secondOrderPartialFill) {
        LimitOrder.Data storage limitOrderData = LimitOrder.load();

        if (firstOrder.allowPartialMatching) {
            firstOrder.sizeDelta = limitOrderData.getRemainingLimitOrderAmount(
                firstOrder.accountId,
                firstOrder.nonce,
                firstOrder.sizeDelta
            );
        }

        if (secondOrder.allowPartialMatching) {
            secondOrder.sizeDelta = limitOrderData.getRemainingLimitOrderAmount(
                secondOrder.accountId,
                secondOrder.nonce,
                secondOrder.sizeDelta
            );
        }

        if (firstOrder.sizeDelta > -secondOrder.sizeDelta && firstOrder.allowPartialMatching) {
            firstOrderPartialFill = true;
            firstOrder.sizeDelta = -secondOrder.sizeDelta;
        } else if (
            firstOrder.sizeDelta < -secondOrder.sizeDelta && secondOrder.allowPartialMatching
        ) {
            secondOrderPartialFill = true;
            secondOrder.sizeDelta = -firstOrder.sizeDelta;
        }
    }

    function validateLimitOrder(OffchainOrder.Data memory order) public view {
        AsyncOrder.checkPendingOrder(order.accountId);
        PerpsAccount.validateMaxPositions(order.accountId, order.marketId);
        GlobalPerpsMarket.load().checkLiquidation(order.accountId);

        if (LimitOrder.load().isLimitOrderNonceUsed(order.accountId, order.nonce)) {
            revert ILimitOrderModule.LimitOrderAlreadyUsed(
                order.accountId,
                order.nonce,
                order.acceptablePrice,
                order.sizeDelta
            );
        }
    }

    function validateLimitOrderPair(
        OffchainOrder.Data memory firstOrder,
        OffchainOrder.Data memory secondOrder
    ) public view {
        if (firstOrder.limitOrderMaker == secondOrder.limitOrderMaker) {
            revert ILimitOrderModule.MismatchingMakerTakerLimitOrder(
                firstOrder.limitOrderMaker,
                secondOrder.limitOrderMaker
            );
        }
        if (firstOrder.referrerOrRelayer != secondOrder.referrerOrRelayer) {
            revert ILimitOrderModule.LimitOrderDifferentRelayer(
                firstOrder.referrerOrRelayer,
                secondOrder.referrerOrRelayer
            );
        }
        if (firstOrder.marketId != secondOrder.marketId) {
            revert ILimitOrderModule.LimitOrderMarketMismatch(
                firstOrder.marketId,
                secondOrder.marketId
            );
        }
        if (firstOrder.expiration <= block.timestamp || secondOrder.expiration <= block.timestamp) {
            revert ILimitOrderModule.LimitOrderExpired(
                firstOrder.accountId,
                firstOrder.expiration,
                secondOrder.accountId,
                secondOrder.expiration,
                block.timestamp
            );
        }
        if (firstOrder.sizeDelta >= 0 || (firstOrder.sizeDelta != -secondOrder.sizeDelta)) {
            revert ILimitOrderModule.LimitOrderAmountError(
                firstOrder.sizeDelta,
                secondOrder.sizeDelta
            );
        }
    }

    function validateLimitOrderRequest(
        OffchainOrder.Data memory order,
        uint256 lastPriceCheck,
        PerpsMarketConfiguration.Data storage marketConfig,
        PerpsMarket.Data storage perpsMarketData
    ) internal view returns (uint256, Position.Data storage oldPosition, Position.Data memory) {
        LimitOrder.ValidateRequestRuntime memory runtime;
        runtime.amount = order.sizeDelta;
        runtime.accountId = order.accountId;
        runtime.marketId = order.marketId;
        runtime.price = order.acceptablePrice;

        PerpsAccount.Data storage account = PerpsAccount.load(runtime.accountId);
        (
            runtime.isEligible,
            runtime.currentAvailableMargin,
            runtime.requiredInitialMargin,
            ,

        ) = account.isEligibleForLiquidation(PerpsPrice.Tolerance.DEFAULT);

        if (runtime.isEligible) {
            revert PerpsAccount.AccountLiquidatable(runtime.accountId);
        }

        runtime.limitOrderFees = getLimitOrderFeesHelper(
            order.sizeDelta,
            order.acceptablePrice,
            order.limitOrderMaker,
            marketConfig
        );

        oldPosition = PerpsMarket.accountPosition(runtime.marketId, runtime.accountId);
        runtime.newPositionSize = oldPosition.size + runtime.amount;

        // only account for negative pnl
        runtime.currentAvailableMargin += MathUtil.min(
            AsyncOrder.calculateFillPricePnl(runtime.price, lastPriceCheck, runtime.amount),
            0
        );
        if (runtime.currentAvailableMargin < runtime.limitOrderFees.toInt()) {
            revert ILimitOrderModule.InsufficientMargin(
                runtime.currentAvailableMargin,
                runtime.limitOrderFees
            );
        }

        runtime.totalRequiredMargin =
            AsyncOrder.getRequiredMarginWithNewPosition(
                account,
                marketConfig,
                runtime.marketId,
                oldPosition.size,
                runtime.newPositionSize,
                runtime.price,
                runtime.requiredInitialMargin
            ) +
            runtime.limitOrderFees;

        if (runtime.currentAvailableMargin < runtime.totalRequiredMargin.toInt()) {
            revert ILimitOrderModule.InsufficientMargin(
                runtime.currentAvailableMargin,
                runtime.totalRequiredMargin
            );
        }
        // TODO add check if this logic below is needed or should be changed
        // int256 lockedCreditDelta = perpsMarketData.requiredCreditForSize(
        //     MathUtil.abs(runtime.newPositionSize).toInt() - MathUtil.abs(oldPosition.size).toInt(),
        //     PerpsPrice.Tolerance.DEFAULT
        // );
        // GlobalPerpsMarket.load().validateMarketCapacity(lockedCreditDelta);

        runtime.newPosition = Position.Data({
            marketId: runtime.marketId,
            latestInteractionPrice: order.acceptablePrice.to128(),
            latestInteractionFunding: perpsMarketData.lastFundingValue.to128(),
            latestInterestAccrued: 0,
            size: runtime.newPositionSize
        });

        return (runtime.limitOrderFees, oldPosition, runtime.newPosition);
    }

    function settleLimitOrder(
        OffchainOrder.Data memory order,
        uint256 limitOrderFees,
        Position.Data storage oldPosition,
        Position.Data memory newPosition,
        bool partialFill
    ) internal {
        LimitOrder.SettleRequestRuntime memory runtime;
        runtime.accountId = order.accountId;
        runtime.marketId = order.marketId;
        runtime.limitOrderFees = limitOrderFees;
        runtime.amount = order.sizeDelta;
        runtime.price = order.acceptablePrice;
        runtime.newPosition = newPosition;

        PerpsAccount.Data storage perpsAccount = PerpsAccount.load(runtime.accountId);
        (runtime.pnl, , runtime.chargedInterest, runtime.accruedFunding, , ) = oldPosition.getPnl(
            order.acceptablePrice
        );

        runtime.chargedAmount = runtime.pnl - runtime.limitOrderFees.toInt();
        perpsAccount.charge(runtime.chargedAmount);
        emit AccountCharged(runtime.accountId, runtime.chargedAmount, perpsAccount.debt);

        // after pnl is realized, update position
        runtime.updateData = PerpsMarket.loadValid(runtime.marketId).updatePositionData(
            runtime.accountId,
            newPosition
        );
        perpsAccount.updateOpenPositions(runtime.marketId, newPosition.size);

        emit MarketUpdated(
            runtime.updateData.marketId,
            runtime.price,
            runtime.updateData.skew,
            runtime.updateData.size,
            runtime.amount,
            runtime.updateData.currentFundingRate,
            runtime.updateData.currentFundingVelocity,
            runtime.updateData.interestRate
        );

        PerpsMarketFactory.Data storage factory = PerpsMarketFactory.load();
        (runtime.relayerFees, runtime.feeCollectorFees) = GlobalPerpsMarketConfiguration
            .load()
            .collectFees(limitOrderFees, order.referrerOrRelayer, factory);

        LimitOrder.Data storage limitOrderData = LimitOrder.load();
        if (partialFill) {
            limitOrderData.updateLimitOrderAmountSettled(
                runtime.accountId,
                order.nonce,
                runtime.amount
            );
        } else {
            limitOrderData.markLimitOrderNonceUsed(runtime.accountId, order.nonce);
        }
        // emit event
        emit ILimitOrderModule.LimitOrderSettled(
            runtime.marketId,
            runtime.accountId,
            order.nonce,
            runtime.price,
            runtime.pnl,
            runtime.accruedFunding,
            runtime.amount,
            runtime.newPosition.size,
            runtime.limitOrderFees,
            runtime.relayerFees,
            runtime.feeCollectorFees,
            runtime.chargedInterest
        );
    }

    function getLimitOrderFeesHelper(
        int128 amount,
        uint256 price,
        bool isMaker,
        PerpsMarketConfiguration.Data storage marketConfig
    ) internal view returns (uint256) {
        uint256 fees = isMaker
            ? marketConfig.limitOrderFees.makerFee
            : marketConfig.limitOrderFees.takerFee;

        return MathUtil.abs(amount).mulDecimal(price).mulDecimal(fees);
    }

    function checkCancelOrderSigPermission(
        LimitOrder.CancelOrderRequest memory order,
        LimitOrder.Signature calldata sig
    ) internal {
        Account.exists(order.accountId);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
                keccak256(abi.encode(_CANCEL_ORDER_TYPEHASH, order.accountId, order.nonce))
            )
        );
        address signingAddress = ecrecover(digest, sig.v, sig.r, sig.s);

        Account.loadAccountAndValidateSignerPermission(
            order.accountId,
            AccountRBAC._PERPS_CANCEL_LIMIT_ORDER,
            signingAddress
        );
    }

    function domainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("PolynomialPerpetualFutures")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(this)
                )
            );
    }

    function checkSigPermission(
        OffchainOrder.Data memory order,
        OffchainOrder.Signature memory sig
    ) internal {
        Account.exists(order.accountId);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
                keccak256(
                    abi.encode(
                        _ORDER_TYPEHASH,
                        order.marketId,
                        order.accountId,
                        order.sizeDelta,
                        order.settlementStrategyId,
                        order.referrerOrRelayer,
                        order.allowAggregation,
                        order.allowPartialMatching,
                        order.acceptablePrice,
                        order.trackingCode,
                        order.expiration,
                        order.nonce
                    )
                )
            )
        );
        address signingAddress = ecrecover(digest, sig.v, sig.r, sig.s);

        Account.loadAccountAndValidateSignerPermission(
            order.accountId,
            AccountRBAC._PERPS_COMMIT_OFFCHAIN_ORDER_PERMISSION,
            signingAddress
        );
    }
}
