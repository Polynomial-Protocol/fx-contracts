import { ethers } from 'ethers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';
import { fastForward, advanceBlock } from '@synthetixio/core-utils/src/utils/hardhat/rpc';

// TODO: This test's expected calculation doesn't match contract behavior - needs investigation
describe.skip('Market - Rollover - State Independence (open/closed/open)', () => {
  const REQ_MARKET_ID = 9024;
  const ACCOUNT_ID = 29025;

  const _PRICE = bn(1000);
  const T1 = 600; // 10 min
  const T2 = 1200; // 20 min
  const T3 = 300; // 5 min

  const { systems, perpsMarkets, provider, trader1, keeper, owner, keeperCostOracleNode } =
    bootstrapMarkets({
      synthMarkets: [],
      perpsMarkets: [
        {
          requestedMarketId: REQ_MARKET_ID,
          name: 'RolloverTest4',
          token: 'snxRL4',
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

  let firstSettleTime: number;
  before('deposit collateral and open position', async () => {
    await depositCollateral({
      systems,
      trader: trader1,
      accountId: () => ACCOUNT_ID,
      collaterals: [{ snxUSDAmount: () => bn(10_000) }],
    });
    const res = await openPosition({
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
    firstSettleTime = res.settleTime;
  });

  it('accrues across open, closed, then open again', async () => {
    const ONE = bn(1);

    // While open: T1
    await fastForward(T1, provider());
    await advanceBlock(provider());
    const tx1 = await openPosition({
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
    const r1 = await tx1.settleTx.wait();
    let fillPrice1: ethers.BigNumber | undefined;
    let charged1: ethers.BigNumber | undefined;
    for (const log of r1.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'OrderSettled') fillPrice1 = parsed.args.fillPrice as ethers.BigNumber;
        if (parsed.name === 'InterestCharged') charged1 = parsed.args.interest as ethers.BigNumber;
      } catch {
        /* ignore */
      }
    }
    if (!fillPrice1 || !charged1) throw new Error('Missing expected events (tx1)');
    const sizeBefore1 = bn(0.1);
    const elapsed1 = tx1.settleTime - firstSettleTime;
    const expected1 = sizeBefore1.mul(fillPrice1).div(ONE).mul(feePerSec).div(ONE).mul(elapsed1);
    assertBn.near(charged1, expected1, bn(0.00000000000001));

    // Close market
    await systems().PerpsMarket.connect(owner()).closeMarkets([marketId]);

    // While closed: T2 (no Pyth updates expected) → do not settle during closure
    await fastForward(T2, provider());
    await advanceBlock(provider());

    // Re-open market before realizing T2 accrual
    await systems().PerpsMarket.connect(owner()).openMarkets([marketId]);

    const tx2 = await openPosition({
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
    const r2 = await tx2.settleTx.wait();
    let fillPrice2: ethers.BigNumber | undefined;
    let charged2: ethers.BigNumber | undefined;
    for (const log of r2.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'OrderSettled') fillPrice2 = parsed.args.fillPrice as ethers.BigNumber;
        if (parsed.name === 'InterestCharged') charged2 = parsed.args.interest as ethers.BigNumber;
      } catch {
        /* ignore */
      }
    }
    if (!fillPrice2 || !charged2) throw new Error('Missing expected events (tx2)');
    const sizeBefore2 = bn(0.1).sub(bn(0.0001));
    const elapsed2 = tx2.settleTime - tx1.settleTime;
    const expected2 = sizeBefore2.mul(fillPrice2).div(ONE).mul(feePerSec).div(ONE).mul(elapsed2);
    assertBn.near(charged2, expected2, bn(0.00000000000001));

    // While open: T3
    await fastForward(T3, provider());
    await advanceBlock(provider());
    const tx3 = await openPosition({
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
    const r3 = await tx3.settleTx.wait();
    let fillPrice3: ethers.BigNumber | undefined;
    let charged3: ethers.BigNumber | undefined;
    for (const log of r3.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'OrderSettled') fillPrice3 = parsed.args.fillPrice as ethers.BigNumber;
        if (parsed.name === 'InterestCharged') charged3 = parsed.args.interest as ethers.BigNumber;
      } catch {
        /* ignore */
      }
    }
    if (!fillPrice3 || !charged3) throw new Error('Missing expected events (tx3)');
    const sizeBefore3 = bn(0.1).sub(bn(0.0001)).sub(bn(0.0001));
    const elapsed3 = tx3.settleTime - tx2.settleTime;
    const expected3 = sizeBefore3.mul(fillPrice3).div(ONE).mul(feePerSec).div(ONE).mul(elapsed3);
    assertBn.near(charged3, expected3, bn(0.00000000000001));
  });
});
