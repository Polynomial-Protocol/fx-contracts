import { ethers } from 'ethers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import assertRevert from '@synthetixio/core-utils/src/utils/assertions/assert-revert';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';
import { fastForward, advanceBlock } from '@synthetixio/core-utils/src/utils/hardhat/rpc';

describe('Market - Rollover - Config', () => {
  const REQ_MARKET_ID = 9026;
  const ACCOUNT_ID = 29027;

  const _PRICE = bn(1000);
  const T1 = 600; // 10 min
  const T2 = 900; // 15 min

  const { systems, perpsMarkets, provider, trader1, keeper, owner, signers, keeperCostOracleNode } =
    bootstrapMarkets({
      synthMarkets: [],
      perpsMarkets: [
        {
          requestedMarketId: REQ_MARKET_ID,
          name: 'RolloverTest6',
          token: 'snxRL6',
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
  let randomUser: ethers.Signer;

  before('identify market and roles', () => {
    marketId = perpsMarkets()[0].marketId();
    strategyId = perpsMarkets()[0].strategyId();
    randomUser = signers()[7];
  });

  before('zero fees and keeper costs', async () => {
    await configureZeroFeesAndKeeperCosts({
      systems,
      owner,
      marketId,
      strategyId,
      keeperCostOracleNode,
    });
  });

  it('owner-only setRolloverFee', async () => {
    await assertRevert(
      systems().PerpsMarket.connect(randomUser).setRolloverFee(marketId, 1),
      'Unauthorized',
      systems().PerpsMarket
    );
  });

  it('getRolloverFee returns configured rate and handles mid-interval change', async () => {
    const F1 = bn(1).div(86400);
    const F2 = bn(2).div(86400);
    await systems().PerpsMarket.connect(owner()).setRolloverFee(marketId, F1);
    assertBn.equal(await systems().PerpsMarket.getRolloverFee(marketId), F1);

    // deposit and open
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
      sizeDelta: bn(0.2),
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });
    firstSettleTime = res.settleTime;

    // const notional = bn(0.2).mul(_PRICE);

    // accrue under F1 for T1
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
    // Parse events and compute expected using actual fillPrice and elapsed seconds
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
    const elapsed1 = tx1.settleTime - firstSettleTime;
    const sizeBefore1 = bn(0.2);
    const notional1 = sizeBefore1.mul(fillPrice1).div(ONE);
    const R1 = notional1.mul(F1).div(ONE).mul(elapsed1);
    assertBn.near(charged1, R1, bn(0.00000000000001));

    // change to F2
    await systems().PerpsMarket.connect(owner()).setRolloverFee(marketId, F2);
    assertBn.equal(await systems().PerpsMarket.getRolloverFee(marketId), F2);

    // accrue under F2 for T2
    await fastForward(T2, provider());
    await advanceBlock(provider());
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
    const sizeBefore2 = bn(0.2).sub(bn(0.0001));
    const notional2 = sizeBefore2.mul(fillPrice2).div(ONE);
    const R2 = notional2.mul(F2).div(ONE).mul(elapsed2);
    assertBn.near(charged2, R2, bn(0.00000000000001));
  });
});
