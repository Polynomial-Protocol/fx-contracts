import { ethers } from 'ethers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';

describe('Liquidation - closed then reopen price usage', () => {
  const REQ_MARKET_ID = 9041;
  const ACCOUNT_ID = 29041;
  const _PRICE = bn(1000);

  const { systems, perpsMarkets, provider, trader1, keeper, owner, keeperCostOracleNode } =
    bootstrapMarkets({
      synthMarkets: [],
      perpsMarkets: [
        {
          requestedMarketId: REQ_MARKET_ID,
          name: 'ClosedReopenLiq',
          token: 'snxCRL',
          price: _PRICE,
          fundingParams: { skewScale: bn(1_000_000), maxFundingVelocity: bn(0) },
          orderFees: { makerFee: bn(0), takerFee: bn(0) },
        },
      ],
      traderAccountIds: [ACCOUNT_ID],
    });

  let marketId: ethers.BigNumber;
  before('identify market', () => {
    marketId = perpsMarkets()[0].marketId();
  });

  before('zero fees, keeper costs, settlement reward', async () => {
    await configureZeroFeesAndKeeperCosts({
      systems,
      owner,
      marketId,
      strategyId: perpsMarkets()[0].strategyId(),
      keeperCostOracleNode,
    });
  });

  before('deposit collateral and open position', async () => {
    await depositCollateral({
      systems,
      trader: trader1,
      accountId: () => ACCOUNT_ID,
      collaterals: [{ snxUSDAmount: () => bn(2_000) }],
    });
    await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_ID,
      sizeDelta: bn(1),
      settlementStrategyId: perpsMarkets()[0].strategyId(),
      price: _PRICE,
      keeper: keeper(),
    });
    // Make eligible post-open by requiring a high minimum position margin
    await systems()
      .PerpsMarket.connect(owner())
      .setLiquidationParameters(marketId, bn(0), bn(0), bn(0), bn(0), bn(5_000));
  });

  it('uses close price while closed, then fresh price after reopen', async () => {
    // Close market
    await systems().PerpsMarket.connect(owner()).closeMarkets([marketId]);
    // Change oracle
    await perpsMarkets()[0].aggregator().mockSetCurrentPrice(bn(777));

    // Attempt liquidation while closed → MarketUpdated should see close price (1000)
    const txClosed = await systems().PerpsMarket.connect(keeper()).liquidate(ACCOUNT_ID);
    const rc1 = await txClosed.wait();
    let seenClosed = false;
    for (const log of rc1.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'MarketUpdated' && parsed.args.marketId.eq(marketId)) {
          assertBn.equal(parsed.args.price, _PRICE);
          seenClosed = true;
        }
      } catch {
        /* ignore */
      }
    }
    if (!seenClosed) throw new Error('Closed market MarketUpdated not observed');

    // Reopen
    await systems().PerpsMarket.connect(owner()).openMarkets([marketId]);

    // Replenish and open a new small position so liquidation can run again
    await systems()
      .PerpsMarket.connect(owner())
      .setLiquidationParameters(marketId, bn(0), bn(0), bn(0), bn(0), bn(0));
    await depositCollateral({
      systems,
      trader: trader1,
      accountId: () => ACCOUNT_ID,
      collaterals: [{ snxUSDAmount: () => bn(1_000) }],
    });
    await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_ID,
      sizeDelta: bn(0.1),
      settlementStrategyId: perpsMarkets()[0].strategyId(),
      price: bn(777),
      keeper: keeper(),
    });
    await systems()
      .PerpsMarket.connect(owner())
      .setLiquidationParameters(marketId, bn(0), bn(0), bn(0), bn(0), bn(5_000));

    // Another liquidation attempt should now see fresh price (777)
    const txOpen = await systems().PerpsMarket.connect(keeper()).liquidate(ACCOUNT_ID);
    const rc2 = await txOpen.wait();
    let seenOpen = false;
    for (const log of rc2.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'MarketUpdated' && parsed.args.marketId.eq(marketId)) {
          assertBn.equal(parsed.args.price, bn(777));
          seenOpen = true;
        }
      } catch {
        /* ignore */
      }
    }
    if (!seenOpen) throw new Error('Open market MarketUpdated not observed');
  });
});
