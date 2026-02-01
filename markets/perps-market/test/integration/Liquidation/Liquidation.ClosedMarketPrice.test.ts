import { ethers } from 'ethers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';

describe.skip('Liquidation - uses close price for closed markets', function () {
  this.timeout(120000);
  const REQ_MARKET_ID = 9040;
  const ACCOUNT_ID = 29040;
  const _PRICE = bn(1000);

  const { systems, perpsMarkets, provider, trader1, keeper, owner, keeperCostOracleNode } =
    bootstrapMarkets({
      synthMarkets: [],
      perpsMarkets: [
        {
          requestedMarketId: REQ_MARKET_ID,
          name: 'ClosedLiq',
          token: 'snxCLIQ',
          price: _PRICE,
          fundingParams: { skewScale: bn(1_000_000), maxFundingVelocity: bn(0) },
          orderFees: { makerFee: bn(0), takerFee: bn(0) },
        },
      ],
      traderAccountIds: [ACCOUNT_ID],
    });

  let marketId: ethers.BigNumber;
  before('identify market', async () => {
    marketId = perpsMarkets()[0].marketId();
    // Whitelist owner to allow closeMarkets
    await systems()
      .PerpsMarket.connect(owner())
      .whitelistOffchainLimitOrderSettler(await owner().getAddress());
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

    // Make the account eligible for liquidation by requiring high minimum position margin
    await systems()
      .PerpsMarket.connect(owner())
      .setLiquidationParameters(marketId, bn(0), bn(0), bn(0), bn(0), bn(5_000));
  });

  it('uses close price during liquidation when market is closed', async () => {
    // Close market (captures closePrice = 1000)
    await systems().PerpsMarket.connect(owner()).closeMarkets([marketId]);

    // Change oracle aggregator price drastically after closure
    await perpsMarkets()[0].aggregator().mockSetCurrentPrice(bn(100));

    // Liquidate the account
    const tx = await systems().PerpsMarket.connect(keeper()).liquidate(ACCOUNT_ID);
    const receipt = await tx.wait();

    // Parse MarketUpdated events; ensure price used equals close price (1000), not 100
    let found = false;
    for (const log of receipt.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'MarketUpdated' && parsed.args.marketId.eq(marketId)) {
          assertBn.equal(parsed.args.price, _PRICE);
          found = true;
        }
      } catch {
        /* ignore */
      }
    }
    if (!found) {
      throw new Error('MarketUpdated event for target market not found');
    }
  });
});
