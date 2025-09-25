import { ethers } from 'ethers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';
import { fastForward, advanceBlock } from '@synthetixio/core-utils/src/utils/hardhat/rpc';

describe('Market - Rollover - Baseline Reset', () => {
  const REQ_MARKET_ID = 9022;
  const ACCOUNT_ID = 29022;

  const _PRICE = bn(1000);
  const ONE_HOUR = 3600;

  const { systems, perpsMarkets, provider, trader1, keeper, owner, keeperCostOracleNode } =
    bootstrapMarkets({
      synthMarkets: [],
      perpsMarkets: [
        {
          requestedMarketId: REQ_MARKET_ID,
          name: 'RolloverTest2',
          token: 'snxRL2',
          price: _PRICE,
          fundingParams: { skewScale: bn(1_000_000), maxFundingVelocity: bn(0) },
          orderFees: { makerFee: bn(0), takerFee: bn(0) },
        },
      ],
      traderAccountIds: [ACCOUNT_ID],
    });

  let marketId: ethers.BigNumber;
  let strategyId: ethers.BigNumber;
  let firstSettleTime: number;

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

  before('deposit collateral', async () => {
    await depositCollateral({
      systems,
      trader: trader1,
      accountId: () => ACCOUNT_ID,
      collaterals: [{ snxUSDAmount: () => bn(10_000) }],
    });
  });

  before('open small long position', async () => {
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

  it('charges R1 then ~0, then R2 after delay', async () => {
    // First accrual over T1
    await fastForward(ONE_HOUR, provider());
    await advanceBlock(provider());
    const tx1 = await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_ID,
      sizeDelta: bn(-0.0001), // tiny reduce to trigger update
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });
    // Parse events
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
    if (!fillPrice1 || !charged1) throw new Error('Missing expected events in tx1');
    const ONE = bn(1);
    const sizeBefore1 = bn(0.1);
    const elapsed1 = tx1.settleTime - firstSettleTime;
    const notional1 = sizeBefore1.mul(fillPrice1).div(ONE);
    const expectedR1 = notional1.mul(feePerSec).div(ONE).mul(elapsed1);
    assertBn.near(charged1, expectedR1, bn(0.00000000000001));

    // Immediately settle another tiny reduce without time; expect ~0
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
    if (!fillPrice2 || !charged2) throw new Error('Missing expected events in tx2');
    const elapsed2 = tx2.settleTime - tx1.settleTime;
    const sizeBefore2 = bn(0.1).sub(bn(0.0001));
    const notional2 = sizeBefore2.mul(fillPrice2).div(bn(1));
    const expectedRmid = notional2.mul(feePerSec).div(bn(1)).mul(elapsed2);
    assertBn.near(charged2, expectedRmid, bn(0.00000000000001));

    // Fast-forward T2 and expect R2
    await fastForward(ONE_HOUR, provider());
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
    if (!fillPrice3 || !charged3) throw new Error('Missing expected events in tx3');
    const sizeBefore3 = bn(0.1).sub(bn(0.0001)).sub(bn(0.0001));
    const elapsed3 = tx3.settleTime - tx2.settleTime;
    const notional3 = sizeBefore3.mul(fillPrice3).div(ONE);
    const expectedR2 = notional3.mul(feePerSec).div(ONE).mul(elapsed3);
    assertBn.near(charged3, expectedR2, bn(0.00000000000001));
  });
});
