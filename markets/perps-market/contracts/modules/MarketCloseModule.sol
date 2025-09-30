//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IMarketCloseModule} from "../interfaces/IMarketCloseModule.sol";
import {MarketClose} from "../storage/MarketClose.sol";
import {OwnableStorage} from "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import {PerpsPrice} from "../storage/PerpsPrice.sol";
import {PerpsMarketConfiguration} from "../storage/PerpsMarketConfiguration.sol";
import {PerpsMarket} from "../storage/PerpsMarket.sol";
import {PerpsAccount} from "../storage/PerpsAccount.sol";
import {Position} from "../storage/Position.sol";
import {FeatureFlag} from "@synthetixio/core-modules/contracts/storage/FeatureFlag.sol";
import {Flags} from "../utils/Flags.sol";
import {GlobalPerpsMarket} from "../storage/GlobalPerpsMarket.sol";
import {GlobalPerpsMarketConfiguration} from "../storage/GlobalPerpsMarketConfiguration.sol";
import {ERC2771Context} from "@synthetixio/core-contracts/contracts/utils/ERC2771Context.sol";
import {IPythERC7412Wrapper} from "../interfaces/external/IPythERC7412Wrapper.sol";
import {PerpsMarketFactory} from "../storage/PerpsMarketFactory.sol";
import {KeeperCosts} from "../storage/KeeperCosts.sol";
import {FeeTier} from "../storage/FeeTier.sol";
import {IAsyncOrderSettlementPythModule} from "../interfaces/IAsyncOrderSettlementPythModule.sol";
import {AsyncOrder} from "../storage/AsyncOrder.sol";
import {DecimalMath} from "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";
import {SafeCastI256, SafeCastU256, SafeCastI128} from "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import {GlobalPerpsMarketConfiguration} from "../storage/GlobalPerpsMarketConfiguration.sol";
import {SettlementStrategy} from "../storage/SettlementStrategy.sol";
import {SetUtil} from "@synthetixio/core-contracts/contracts/utils/SetUtil.sol";

contract MarketCloseModule is IMarketCloseModule {
    using MarketClose for MarketClose.Data;
    using PerpsMarket for PerpsMarket.Data;
    using DecimalMath for int128;
    using DecimalMath for uint256;
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;
    using SafeCastI128 for int128;
    using PerpsAccount for PerpsAccount.Data;
    using GlobalPerpsMarketConfiguration for GlobalPerpsMarketConfiguration.Data;
    using KeeperCosts for KeeperCosts.Data;
    using GlobalPerpsMarket for GlobalPerpsMarket.Data;
    using Position for Position.Data;
    using PerpsMarketFactory for PerpsMarketFactory.Data;
    using SetUtil for SetUtil.UintSet;

    /**
     * @inheritdoc IMarketCloseModule
     */
    function closeMarkets(uint128[] calldata marketIds) external override {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);
        OwnableStorage.onlyOwner();
        for (uint256 i = 0; i < marketIds.length; i++) {
            PerpsMarket.loadValid(marketIds[i]);
            MarketClose.Data storage market = MarketClose.load(marketIds[i]);
            market.isClosed = true;
            market.closeTime = block.timestamp;
            market.closePrice = PerpsPrice.getCurrentPrice(
                marketIds[i],
                PerpsPrice.Tolerance.STRICT
            );

            emit MarketClosed(marketIds[i], block.timestamp, market.closePrice);
        }
    }

    /**
     * @inheritdoc IMarketCloseModule
     */
    function closeMarketsWithTimestamps(
        uint128[] calldata marketIds,
        uint256[] calldata timestamps
    ) external override {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);
        OwnableStorage.onlyOwner();
        for (uint256 i = 0; i < marketIds.length; i++) {
            PerpsMarket.loadValid(marketIds[i]);
            MarketClose.Data storage market = MarketClose.load(marketIds[i]);
            market.isClosed = true;
            market.closeTime = timestamps[i];

            // Get settlement strategy (id = 0) for feed and wrapper
            PerpsMarketConfiguration.Data storage marketConfig = PerpsMarketConfiguration.load(
                marketIds[i]
            );
            SettlementStrategy.Data storage strategy = marketConfig.settlementStrategies[0];

            // Get close price from Pyth Benchmarks
            market.closePrice = IPythERC7412Wrapper(strategy.priceVerificationContract)
                .getBenchmarkPrice(strategy.feedId, timestamps[i].to64())
                .toUint();

            emit MarketClosed(marketIds[i], timestamps[i], market.closePrice);
        }
    }

    /**
     * @inheritdoc IMarketCloseModule
     */
    function openMarkets(uint128[] calldata marketIds) external override {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);
        OwnableStorage.onlyOwner();
        for (uint256 i = 0; i < marketIds.length; i++) {
            PerpsMarket.loadValid(marketIds[i]);
            MarketClose.Data storage market = MarketClose.load(marketIds[i]);
            market.isClosed = false;
            market.openTime = block.timestamp;

            emit MarketsOpened(marketIds[i]);
        }
    }

    function closePosition(uint128 accountId, uint128 marketId) external override {
        FeatureFlag.ensureAccessToFeature(Flags.PERPS_SYSTEM);

        GlobalPerpsMarket.load().checkLiquidation(accountId);

        GlobalPerpsMarketConfiguration.Data storage s = GlobalPerpsMarketConfiguration.load();
        {
            uint256 shareRatioD18 = s.referrerShare[ERC2771Context._msgSender()];
            if (shareRatioD18 == 0) {
                revert UnauthorizedKeeper(ERC2771Context._msgSender());
            }

            uint256 rolloverFee = MarketClose.load(marketId).rolloverFee;
            if (rolloverFee == 0) {
                revert RolloverFeeNotSet(marketId);
            }

            // Check if market is closed
            MarketClose.Data storage market = MarketClose.load(marketId);
            if (market.isClosed) {
                revert MarketAlreadyClosed(marketId);
            }
        }

        // Load core storage
        PerpsMarket.Data storage market = PerpsMarket.load(marketId);
        PerpsAccount.Data storage perpsAccount = PerpsAccount.load(accountId);
        Position.Data storage oldPosition = PerpsMarket.accountPosition(marketId, accountId);

        MarketCloseRuntime memory runtime;

        // If no position, nothing to do
        if (oldPosition.size == 0) {
            return;
        }

        // Load settlement strategy (id = 0) for feed and wrapper
        PerpsMarketConfiguration.Data storage marketConfig = PerpsMarketConfiguration.load(
            marketId
        );
        SettlementStrategy.Data storage strategy = marketConfig.settlementStrategies[0];

        // Fetch latest oracle price with 60s tolerance and recompute funding
        uint256 orderPrice = IPythERC7412Wrapper(strategy.priceVerificationContract)
            .getLatestPrice(strategy.feedId, 60)
            .toUint();
        market.recomputeFunding(orderPrice);

        // Compute sizeDelta to fully close and compute fill price including PD
        runtime.sizeDelta = -oldPosition.size;
        runtime.fillPrice = AsyncOrder.calculateFillPrice(
            market.skew,
            marketConfig.skewScale,
            runtime.sizeDelta,
            orderPrice
        );

        // Calculate total fees (order fees + settlement reward)
        FeeTier.Data storage feeTier = FeeTier.load(perpsAccount.feeTierId);
        runtime.orderFees = AsyncOrder.calculateOrderFee(
            runtime.sizeDelta,
            runtime.fillPrice,
            market.skew,
            FeeTier.getFees(feeTier, marketConfig.orderFees)
        );
        runtime.settlementReward = AsyncOrder.settlementRewardCost(strategy);
        runtime.totalFees = runtime.orderFees + runtime.settlementReward;

        // Realize PnL at fillPrice
        (runtime.pnl, , runtime.chargedInterest, runtime.accruedFunding, , ) = oldPosition.getPnl(
            runtime.fillPrice
        );
        runtime.chargedAmount = runtime.pnl - runtime.totalFees.toInt();
        perpsAccount.charge(runtime.chargedAmount);

        // Update position to size 0 at fill price baselines
        Position.Data memory newPosition = Position.Data({
            marketId: marketId,
            // solhint-disable-next-line numcast/safe-cast
            size: int128(0),
            latestInteractionPrice: runtime.fillPrice.to128(),
            latestInteractionFunding: market.lastFundingValue.to128(),
            latestInterestAccrued: 0,
            latestRolloverAccruedAt: 0
        });

        market.updatePositionData(accountId, newPosition);
        perpsAccount.updateOpenPositions(marketId, newPosition.size);

        // Process fees (keeper rewards + protocol/referrer split)
        PerpsMarketFactory.Data storage factory = PerpsMarketFactory.load();

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

        // Remaining fees (excluding keeper reward) routed via fee collector logic; no referrer
        (runtime.referralFees, runtime.feeCollectorFees) = s.collectFees(
            runtime.totalFees - runtime.settlementReward,
            address(0),
            factory
        );

        emitSettlementEvents(runtime, marketId, accountId);
    }

    /**
     * @inheritdoc IMarketCloseModule
     */
    function setRolloverFee(uint128 marketId, uint256 rolloverFee) external override {
        OwnableStorage.onlyOwner();
        MarketClose.load(marketId).rolloverFee = rolloverFee;
        emit RolloverFeeSet(marketId, rolloverFee);
    }

    /**
     * @inheritdoc IMarketCloseModule
     */
    function getRolloverFee(uint128 marketId) external view override returns (uint256) {
        return MarketClose.load(marketId).rolloverFee;
    }

    function emitSettlementEvents(
        MarketCloseRuntime memory runtime,
        uint128 marketId,
        uint128 accountId
    ) internal {
        emit IAsyncOrderSettlementPythModule.InterestCharged(accountId, runtime.chargedInterest);

        emit IAsyncOrderSettlementPythModule.OrderSettled(
            marketId,
            accountId,
            runtime.fillPrice,
            runtime.pnl,
            runtime.accruedFunding,
            runtime.sizeDelta,
            // solhint-disable-next-line numcast/safe-cast
            int128(0),
            runtime.totalFees,
            runtime.referralFees,
            runtime.feeCollectorFees,
            runtime.settlementReward,
            bytes32(0),
            ERC2771Context._msgSender()
        );
    }
}
