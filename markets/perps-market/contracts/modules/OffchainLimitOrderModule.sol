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

    // keccak256("OffchainOrder(uint128 marketId,uint128 accountId,int128 sizeDelta,uint128 settlementStrategyId,address referrerOrRelayer,bool allowAggregation,bool allowPartialMatching,bool reduceOnly,uint256 acceptablePrice,bytes32 trackingCode,uint256 expiration,uint256 nonce)");
    bytes32 private constant _ORDER_TYPEHASH =
        0xfa2db4cbdb01b350b8ce55fb85ef8bd1b19e1e933b085005ee10f6d931c67519;

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
        OffchainOrder.Data memory shortOrder,
        OffchainOrder.Signature memory shortSignature,
        OffchainOrder.Data memory longOrder,
        OffchainOrder.Signature memory longSignature
    ) external {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);
        FeatureFlag.ensureAccessToFeature(Flags.LIMIT_ORDER);
        PerpsMarket.loadValid(shortOrder.marketId);
        Account.exists(shortOrder.accountId);
        Account.exists(longOrder.accountId);

        checkSigPermission(shortOrder, shortSignature);
        checkSigPermission(longOrder, longSignature);

        LimitOrder.LimitOrderPartialFillData memory partialFillData;

        uint256 lastPriceCheck;
        {
            SettlementStrategy.Data storage strategy = PerpsMarketConfiguration
                .loadValidSettlementStrategy(shortOrder.marketId, shortOrder.settlementStrategyId);

            lastPriceCheck = IPythERC7412Wrapper(strategy.priceVerificationContract)
                .getLatestPrice(
                    strategy.feedId,
                    30 // 30 seconds
                )
                .toUint();
        }

        PerpsMarket.Data storage perpsMarketData = PerpsMarket.load(shortOrder.marketId);
        perpsMarketData.recomputeFunding(lastPriceCheck);

        PerpsMarketConfiguration.Data storage marketConfig = PerpsMarketConfiguration.load(
            shortOrder.marketId
        );

        (
            partialFillData.firstOrderPartialFill,
            partialFillData.secondOrderPartialFill
        ) = updateLimitOrderAmounts(shortOrder, longOrder);

        perpsMarketData.validateLimitOrderSize(
            marketConfig.maxMarketSize,
            marketConfig.maxMarketValue,
            shortOrder.acceptablePrice,
            shortOrder.sizeDelta
        );

        validateLimitOrder(shortOrder);
        validateLimitOrder(longOrder);
        validateLimitOrderPair(shortOrder, longOrder);

        validateRelayerAndSettler(shortOrder.referrerOrRelayer);

        if (shortOrder.limitOrderMaker) {
            longOrder.acceptablePrice = shortOrder.acceptablePrice;
        } else {
            shortOrder.acceptablePrice = longOrder.acceptablePrice;
        }

        (
            uint256 firstLimitOrderFees,
            Position.Data storage firstOldPosition,
            Position.Data memory firstNewPosition
        ) = validateLimitOrderRequest(shortOrder, lastPriceCheck, marketConfig, perpsMarketData);
        (
            uint256 secondLimitOrderFees,
            Position.Data storage secondOldPosition,
            Position.Data memory secondNewPosition
        ) = validateLimitOrderRequest(longOrder, lastPriceCheck, marketConfig, perpsMarketData);

        settleLimitOrder(
            shortOrder,
            firstLimitOrderFees,
            lastPriceCheck,
            firstOldPosition,
            firstNewPosition,
            partialFillData.firstOrderPartialFill
        );
        settleLimitOrder(
            longOrder,
            secondLimitOrderFees,
            lastPriceCheck,
            secondOldPosition,
            secondNewPosition,
            partialFillData.secondOrderPartialFill
        );
    }

    function updateLimitOrderAmounts(
        OffchainOrder.Data memory shortOrder,
        OffchainOrder.Data memory longOrder
    ) internal returns (bool firstOrderPartialFill, bool secondOrderPartialFill) {
        LimitOrder.Data storage limitOrderData = LimitOrder.load();

        if (shortOrder.reduceOnly) {
            int128 currentSize = PerpsMarket
                .accountPosition(shortOrder.marketId, shortOrder.accountId)
                .size;

            if (MathUtil.sameSide(currentSize, shortOrder.sizeDelta)) {
                revert OffchainOrder.ReduceOnlyOrder(currentSize, shortOrder.sizeDelta);
            }

            if (MathUtil.abs(currentSize) <= MathUtil.abs(shortOrder.sizeDelta)) {
                shortOrder.sizeDelta = -currentSize;
            }
        }

        if (longOrder.reduceOnly) {
            int128 currentSize = PerpsMarket
                .accountPosition(longOrder.marketId, longOrder.accountId)
                .size;

            if (MathUtil.sameSide(currentSize, longOrder.sizeDelta)) {
                revert OffchainOrder.ReduceOnlyOrder(currentSize, longOrder.sizeDelta);
            }

            if (MathUtil.abs(currentSize) <= MathUtil.abs(longOrder.sizeDelta)) {
                longOrder.sizeDelta = -currentSize;
            }
        }

        if (shortOrder.allowPartialMatching) {
            shortOrder.sizeDelta = limitOrderData.getRemainingLimitOrderAmount(
                shortOrder.accountId,
                shortOrder.nonce,
                shortOrder.sizeDelta
            );
        }

        if (longOrder.allowPartialMatching) {
            longOrder.sizeDelta = limitOrderData.getRemainingLimitOrderAmount(
                longOrder.accountId,
                longOrder.nonce,
                longOrder.sizeDelta
            );
        }

        if (shortOrder.sizeDelta > -longOrder.sizeDelta && shortOrder.allowPartialMatching) {
            firstOrderPartialFill = true;
            shortOrder.sizeDelta = -longOrder.sizeDelta;
        } else if (shortOrder.sizeDelta < -longOrder.sizeDelta && longOrder.allowPartialMatching) {
            secondOrderPartialFill = true;
            longOrder.sizeDelta = -shortOrder.sizeDelta;
        }
    }

    function validateLimitOrder(OffchainOrder.Data memory order) public view {
        PerpsAccount.validateMaxPositions(order.accountId, order.marketId);
        GlobalPerpsMarket.load().checkLiquidation(order.accountId);

        if (LimitOrder.load().isLimitOrderNonceUsed(order.accountId, order.nonce)) {
            revert ILimitOrderModule.LimitOrderAlreadyUsed(order.accountId, order.nonce);
        }
    }

    function validateRelayerAndSettler(address referrerOrRelayer) internal view {
        GlobalPerpsMarketConfiguration.Data storage store = GlobalPerpsMarketConfiguration.load();
        uint256 shareRatioD18 = store.referrerShare[referrerOrRelayer];
        if (shareRatioD18 == 0) {
            revert ILimitOrderModule.LimitOrderRelayerInvalid(referrerOrRelayer);
        }

        address msgSender = ERC2771Context._msgSender();
        bool isWhitelisted = store.whitelistedOffchainLimitOrderSettlers[msgSender];
        if (!isWhitelisted) {
            revert ILimitOrderModule.OffchainLimitOrderSettlerNotWhitelisted(msgSender);
        }
    }

    function validateLimitOrderPair(
        OffchainOrder.Data memory shortOrder,
        OffchainOrder.Data memory longOrder
    ) public view {
        if (shortOrder.limitOrderMaker == longOrder.limitOrderMaker) {
            revert ILimitOrderModule.MismatchingMakerTakerLimitOrder(
                shortOrder.limitOrderMaker,
                longOrder.limitOrderMaker
            );
        }
        if (shortOrder.referrerOrRelayer != longOrder.referrerOrRelayer) {
            revert ILimitOrderModule.LimitOrderDifferentRelayer(
                shortOrder.referrerOrRelayer,
                longOrder.referrerOrRelayer
            );
        }
        if (shortOrder.marketId != longOrder.marketId) {
            revert ILimitOrderModule.LimitOrderMarketMismatch(
                shortOrder.marketId,
                longOrder.marketId
            );
        }
        if (shortOrder.acceptablePrice > longOrder.acceptablePrice) {
            revert ILimitOrderModule.LimitOrderPriceMismatch(
                shortOrder.acceptablePrice,
                longOrder.acceptablePrice
            );
        }
        if (shortOrder.expiration <= block.timestamp || longOrder.expiration <= block.timestamp) {
            revert ILimitOrderModule.LimitOrderExpired(
                shortOrder.accountId,
                shortOrder.expiration,
                longOrder.accountId,
                longOrder.expiration,
                block.timestamp
            );
        }
        if (shortOrder.sizeDelta >= 0 || (shortOrder.sizeDelta != -longOrder.sizeDelta)) {
            revert ILimitOrderModule.LimitOrderAmountError(
                shortOrder.sizeDelta,
                longOrder.sizeDelta
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
            revert ILimitOrderModule.InsufficientAccountMargin(
                runtime.accountId,
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
            revert ILimitOrderModule.InsufficientAccountMargin(
                runtime.accountId,
                runtime.currentAvailableMargin,
                runtime.totalRequiredMargin
            );
        }

        int256 lockedCreditDelta = perpsMarketData.requiredCreditForSize(
            MathUtil.abs(runtime.newPositionSize).toInt() - MathUtil.abs(oldPosition.size).toInt(),
            PerpsPrice.Tolerance.DEFAULT
        );
        GlobalPerpsMarket.load().validateMarketCapacity(lockedCreditDelta);

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
        uint256 lastPriceCheck,
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
            lastPriceCheck
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
            lastPriceCheck,
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
        address signingAddress = address(0x0);

        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        // solhint-disable-next-line numcast/safe-cast
        if (uint256(sig.s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            signingAddress = ecrecover(digest, sig.v, sig.r, sig.s);
        }

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
                        order.reduceOnly,
                        order.acceptablePrice,
                        order.trackingCode,
                        order.expiration,
                        order.nonce
                    )
                )
            )
        );
        address signingAddress = address(0x0);

        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        // solhint-disable-next-line numcast/safe-cast
        if (uint256(sig.s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            signingAddress = ecrecover(digest, sig.v, sig.r, sig.s);
        }

        Account.loadAccountAndValidateSignerPermission(
            order.accountId,
            AccountRBAC._PERPS_COMMIT_OFFCHAIN_ORDER_PERMISSION,
            signingAddress
        );
    }
}
