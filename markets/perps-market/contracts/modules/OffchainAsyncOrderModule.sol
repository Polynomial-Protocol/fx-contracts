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
import {IAsyncOrderModule} from "../interfaces/IAsyncOrderModule.sol";
import {IMarketEvents} from "../interfaces/IMarketEvents.sol";
import {IAccountEvents} from "../interfaces/IAccountEvents.sol";
import {IAsyncOrderSettlementPythModule} from "../interfaces/IAsyncOrderSettlementPythModule.sol";
import {IOffchainOrderModule} from "../interfaces/IOffchainOrderModule.sol";
import {IOffchainAsyncOrderModule} from "../interfaces/IOffchainAsyncOrderModule.sol";
import {IPythERC7412Wrapper} from "../interfaces/external/IPythERC7412Wrapper.sol";
import {Flags} from "../utils/Flags.sol";
import {MathUtil} from "../utils/MathUtil.sol";

contract OffchainAsyncOrderModule is IOffchainAsyncOrderModule, IMarketEvents, IAccountEvents {
    using SafeCastI256 for int256;
    using SafeCastU256 for uint256;
    using DecimalMath for int128;
    using DecimalMath for uint256;
    using GlobalPerpsMarket for GlobalPerpsMarket.Data;
    using PerpsMarket for PerpsMarket.Data;
    using AsyncOrder for AsyncOrder.Data;
    using PerpsAccount for PerpsAccount.Data;
    using GlobalPerpsMarketConfiguration for GlobalPerpsMarketConfiguration.Data;
    using PerpsMarketConfiguration for PerpsMarketConfiguration.Data;
    using Position for Position.Data;
    using PerpsMarketFactory for PerpsMarketFactory.Data;
    using KeeperCosts for KeeperCosts.Data;
    using OffchainOrder for OffchainOrder.NonceData;

    // keccak256("OffchainOrder(uint128 marketId,uint128 accountId,int128 sizeDelta,uint128 settlementStrategyId,address referrerOrRelayer,bool allowAggregation,bool allowPartialMatching,bool reduceOnly,uint256 acceptablePrice,bytes32 trackingCode,uint256 expiration,uint256 nonce)");
    bytes32 private constant _ORDER_TYPEHASH =
        0xfa2db4cbdb01b350b8ce55fb85ef8bd1b19e1e933b085005ee10f6d931c67519;

    function settleOffchainAsyncOrder(
        OffchainOrder.Data memory offchainOrder,
        OffchainOrder.Signature memory signature
    ) external {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);
        PerpsMarket.loadValid(offchainOrder.marketId);
        Account.exists(offchainOrder.accountId);

        checkSigPermission(offchainOrder, signature);

        GlobalPerpsMarket.load().checkLiquidation(offchainOrder.accountId);

        uint256 shareRatioD18 = GlobalPerpsMarketConfiguration.load().referrerShare[
            ERC2771Context._msgSender()
        ];
        if (shareRatioD18 == 0) {
            revert IOffchainOrderModule.UnauthorizedRelayer(ERC2771Context._msgSender());
        }

        OffchainOrder.NonceData storage offchainOrderNonces = OffchainOrder.load();

        if (
            offchainOrderNonces.isOffchainOrderNonceUsed(
                offchainOrder.accountId,
                offchainOrder.nonce
            )
        ) {
            revert IOffchainOrderModule.OffchainOrderAlreadyUsed(
                offchainOrder.accountId,
                offchainOrder.nonce
            );
        }

        offchainOrderNonces.markOffchainOrderNonceUsed(
            offchainOrder.accountId,
            offchainOrder.nonce
        );

        SettlementStrategy.Data storage strategy = PerpsMarketConfiguration
            .loadValidSettlementStrategy(
                offchainOrder.marketId,
                offchainOrder.settlementStrategyId
            );

        AsyncOrder.Data storage order = AsyncOrder.load(offchainOrder.accountId);

        if (order.request.sizeDelta != 0) {
            // @notice not including the expiration time since it requires the previous settlement strategy to be loaded and enabled, otherwise loading it will revert and will prevent new orders to be committed
            emit IAsyncOrderModule.PreviousOrderExpired(
                order.request.marketId,
                order.request.accountId,
                order.request.sizeDelta,
                order.request.acceptablePrice,
                order.commitmentTime,
                order.request.trackingCode
            );
        }

        order.updateValid(offchainOrder);

        strategy = PerpsMarketConfiguration.loadValidSettlementStrategy(
            offchainOrder.marketId,
            offchainOrder.settlementStrategyId
        );

        order.checkWithinSettlementWindow(strategy);

        int256 offchainPrice = IPythERC7412Wrapper(strategy.priceVerificationContract)
            .getBenchmarkPrice(
                strategy.feedId,
                (order.commitmentTime + strategy.commitmentPriceDelay).to64()
            );

        settleAsyncOrder(offchainPrice.toUint(), order, strategy);
    }

    function settleAsyncOrder(
        uint256 price,
        AsyncOrder.Data storage asyncOrder,
        SettlementStrategy.Data storage settlementStrategy
    ) private {
        /// @dev runtime stores order settlement data; circumvents stack limitations
        IAsyncOrderSettlementPythModule.SettleOrderRuntime memory runtime;

        runtime.accountId = asyncOrder.request.accountId;
        runtime.marketId = asyncOrder.request.marketId;
        runtime.sizeDelta = asyncOrder.request.sizeDelta;

        Position.Data storage oldPosition;

        // Load the market before settlement to capture the original market size
        PerpsMarket.Data storage market = PerpsMarket.loadValid(runtime.marketId);
        uint256 originalMarketSize = market.size;

        // validate order request can be settled; call reverts if not
        (runtime.newPosition, runtime.totalFees, runtime.fillPrice, oldPosition) = asyncOrder
            .validateRequest(settlementStrategy, price);

        // validate final fill price is acceptable relative to price specified by trader
        asyncOrder.validateAcceptablePrice(runtime.fillPrice);

        PerpsMarketFactory.Data storage factory = PerpsMarketFactory.load();
        PerpsAccount.Data storage perpsAccount = PerpsAccount.load(runtime.accountId);

        // use actual fill price to calculate realized pnl
        (runtime.pnl, , runtime.chargedInterest, runtime.accruedFunding, , ) = oldPosition.getPnl(
            runtime.fillPrice
        );

        runtime.chargedAmount = runtime.pnl - runtime.totalFees.toInt();
        perpsAccount.charge(runtime.chargedAmount);

        emit AccountCharged(runtime.accountId, runtime.chargedAmount, perpsAccount.debt);

        // only update position state after pnl has been realized
        runtime.updateData = processPositionUpdate(price, runtime, market, originalMarketSize);
        perpsAccount.updateOpenPositions(runtime.marketId, runtime.newPosition.size);

        if (runtime.totalFees > 0) {
            runtime.settlementReward = AsyncOrder.settlementRewardCost(settlementStrategy);
            // Process fees
            processFees(runtime, asyncOrder, factory);
        }

        // Emit events in a helper function
        emitSettlementEvents(runtime, asyncOrder);

        // Reset the async order
        asyncOrder.reset();
    }

    function processPositionUpdate(
        uint256 price,
        IAsyncOrderSettlementPythModule.SettleOrderRuntime memory runtime,
        PerpsMarket.Data storage market,
        uint256 originalMarketSize
    ) internal returns (MarketUpdate.Data memory) {
        // Update position data
        MarketUpdate.Data memory updateData = market.updatePositionData(
            runtime.accountId,
            runtime.newPosition
        );

        // Calculate the market size delta (change in market size)
        int256 marketSizeDelta = market.size.toInt() - originalMarketSize.toInt();

        // Emit MarketUpdated event
        emit MarketUpdated(
            updateData.marketId,
            price,
            updateData.skew,
            market.size,
            marketSizeDelta,
            updateData.currentFundingRate,
            updateData.currentFundingVelocity,
            updateData.interestRate
        );

        return updateData;
    }

    function processFees(
        IAsyncOrderSettlementPythModule.SettleOrderRuntime memory runtime,
        AsyncOrder.Data storage asyncOrder,
        PerpsMarketFactory.Data storage factory
    ) internal {
        GlobalPerpsMarketConfiguration.Data storage s = GlobalPerpsMarketConfiguration.load();

        // if settlement reward is non-zero, pay keeper
        if (runtime.settlementReward > 0) {
            uint256 committerReward = KeeperCosts.load().getSettlementKeeperCosts() / 2;
            uint256 settlerReward = runtime.settlementReward - committerReward;

            if (s.commitFeeReciever != address(0)) {
                factory.withdrawMarketUsd(s.commitFeeReciever, committerReward);
                factory.withdrawMarketUsd(ERC2771Context._msgSender(), settlerReward);
            } else {
                factory.withdrawMarketUsd(ERC2771Context._msgSender(), runtime.settlementReward);
            }
        }

        // order fees are total fees minus settlement reward
        uint256 orderFees = runtime.totalFees - runtime.settlementReward;
        (runtime.referralFees, runtime.feeCollectorFees) = s.collectFees(
            orderFees,
            asyncOrder.request.referrer,
            factory
        );
    }

    function emitSettlementEvents(
        IAsyncOrderSettlementPythModule.SettleOrderRuntime memory runtime,
        AsyncOrder.Data memory asyncOrder
    ) internal {
        emit IAsyncOrderSettlementPythModule.InterestCharged(
            runtime.accountId,
            runtime.chargedInterest
        );

        emit IAsyncOrderSettlementPythModule.OrderSettled(
            runtime.marketId,
            runtime.accountId,
            runtime.fillPrice,
            runtime.pnl,
            runtime.accruedFunding,
            runtime.sizeDelta,
            runtime.newPosition.size,
            runtime.totalFees,
            runtime.referralFees,
            runtime.feeCollectorFees,
            runtime.settlementReward,
            asyncOrder.request.trackingCode,
            ERC2771Context._msgSender()
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
