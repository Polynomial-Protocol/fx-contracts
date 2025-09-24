import { ethers } from 'ethers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';
import { fastForward, advanceBlock } from '@synthetixio/core-utils/src/utils/hardhat/rpc';

describe('Market - Rollover - DebtAccumulator independence', () => {
  const REQ_MARKET_ID = 9025;
  const ACCOUNT_ID = 29026;

  const _PRICE = bn(1000);
  const T = 900; // 15 min

  const {
    systems,
    perpsMarkets,
    superMarketId,
    provider,
    trader1,
    keeper,
    owner,
    keeperCostOracleNode,
  } = bootstrapMarkets({
    synthMarkets: [],
    perpsMarkets: [
      {
        requestedMarketId: REQ_MARKET_ID,
        name: 'RolloverTest5',
        token: 'snxRL5',
        price: _PRICE,
        fundingParams: { skewScale: bn(1_000_000), maxFundingVelocity: bn(0) },
        orderFees: { makerFee: bn(0), takerFee: bn(0) },
      },
    ],
    traderAccountIds: [ACCOUNT_ID],
  });

  let marketId: ethers.BigNumber;
  let strategyId: ethers.BigNumber;

  before('identify market', () => {
    marketId = perpsMarkets()[0].marketId();
    strategyId = perpsMarkets()[0].strategyId();
  });

  before('zero fees, keeper costs, settlement reward', async () => {
    await configureZeroFeesAndKeeperCosts({
      systems,
      owner,
      marketId,
      strategyId,
      keeperCostOracleNode,
    });
  });

  const feePerSec = bn(1).div(86400);
  before('set rollover fee', async () => {
    await systems().PerpsMarket.connect(owner()).setRolloverFee(marketId, feePerSec);
  });

  before('deposit collateral and open position', async () => {
    await depositCollateral({
      systems,
      trader: trader1,
      accountId: () => ACCOUNT_ID,
      collaterals: [{ snxUSDAmount: () => bn(10_000) }],
    });
    await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_ID,
      sizeDelta: bn(0.1),
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });
  });

  it("debtCorrectionAccumulator doesn't change from pure rollover realization", async () => {
    const debtBefore = await systems().PerpsMarket.reportedDebt(superMarketId());

    await fastForward(T, provider());
    await advanceBlock(provider());
    const res = await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_ID,
      sizeDelta: bn(-0.0001),
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });

    // Confirm rollover was realized (InterestCharged > 0)
    const receipt = await res.settleTx.wait();
    let charged: ethers.BigNumber | undefined;
    for (const log of receipt.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'InterestCharged') charged = parsed.args.interest as ethers.BigNumber;
      } catch {
        /* ignore */
      }
    }
    if (!charged) throw new Error('Missing InterestCharged event');
    assertBn.gt(charged!, bn(0));

    const debtAfter = await systems().PerpsMarket.reportedDebt(superMarketId());
    // reportedDebt excludes rollover; allow a tiny drift from PD/funding snapshot differences
    assertBn.near(debtAfter, debtBefore, bn(0.05));
  });
});
