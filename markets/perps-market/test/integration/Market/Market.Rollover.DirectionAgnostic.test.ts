import { ethers } from 'ethers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';
import { fastForward, advanceBlock } from '@synthetixio/core-utils/src/utils/hardhat/rpc';

describe('Market - Rollover - Direction Agnostic', () => {
  const REQ_MARKET_ID = 9023;
  const ACCOUNT_LONG = 29023;
  const ACCOUNT_SHORT = 29024;

  const _PRICE = bn(1000);
  const T = 1800; // 30 min

  const { systems, perpsMarkets, provider, trader1, trader2, keeper, owner, keeperCostOracleNode } =
    bootstrapMarkets({
      synthMarkets: [],
      perpsMarkets: [
        {
          requestedMarketId: REQ_MARKET_ID,
          name: 'RolloverTest3',
          token: 'snxRL3',
          price: _PRICE,
          fundingParams: { skewScale: bn(1_000_000), maxFundingVelocity: bn(0) },
          orderFees: { makerFee: bn(0), takerFee: bn(0) },
        },
      ],
      traderAccountIds: [ACCOUNT_LONG, ACCOUNT_SHORT],
    });

  let marketId: ethers.BigNumber;
  let strategyId: ethers.BigNumber;
  let firstSettleTimeLong: number;
  let firstSettleTimeShort: number;

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

  before('deposit collateral both accounts', async () => {
    await depositCollateral({
      systems,
      trader: trader1,
      accountId: () => ACCOUNT_LONG,
      collaterals: [{ snxUSDAmount: () => bn(10_000) }],
    });
    await depositCollateral({
      systems,
      trader: trader2,
      accountId: () => ACCOUNT_SHORT,
      collaterals: [{ snxUSDAmount: () => bn(10_000) }],
    });
  });

  before('open equal long and short', async () => {
    const resLong = await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_LONG,
      sizeDelta: bn(0.2),
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });
    firstSettleTimeLong = resLong.settleTime;
    const resShort = await openPosition({
      systems,
      provider,
      trader: trader2(),
      marketId,
      accountId: ACCOUNT_SHORT,
      sizeDelta: bn(-0.2),
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });
    firstSettleTimeShort = resShort.settleTime;
  });

  it('charges identical per-dollar-per-second rollover for long and short after same T', async () => {
    await fastForward(T, provider());
    await advanceBlock(provider());

    const txLong = await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_LONG,
      sizeDelta: bn(-0.0001),
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });
    const txShort = await openPosition({
      systems,
      provider,
      trader: trader2(),
      marketId,
      accountId: ACCOUNT_SHORT,
      sizeDelta: bn(0.0001),
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });
    // Parse events and compute normalized per-dollar-per-second rates
    const rLong = await txLong.settleTx.wait();
    const rShort = await txShort.settleTx.wait();

    let fillPriceLong: ethers.BigNumber | undefined;
    let chargedLong: ethers.BigNumber | undefined;
    for (const log of rLong.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'OrderSettled')
          fillPriceLong = parsed.args.fillPrice as ethers.BigNumber;
        if (parsed.name === 'InterestCharged')
          chargedLong = parsed.args.interest as ethers.BigNumber;
      } catch {
        /* ignore */
      }
    }
    let fillPriceShort: ethers.BigNumber | undefined;
    let chargedShort: ethers.BigNumber | undefined;
    for (const log of rShort.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'OrderSettled')
          fillPriceShort = parsed.args.fillPrice as ethers.BigNumber;
        if (parsed.name === 'InterestCharged')
          chargedShort = parsed.args.interest as ethers.BigNumber;
      } catch {
        /* ignore */
      }
    }

    if (!fillPriceLong || !chargedLong || !fillPriceShort || !chargedShort) {
      throw new Error('Missing expected events');
    }

    const ONE = bn(1);
    const sizeAbs = bn(0.2);
    const elapsedLong = txLong.settleTime - firstSettleTimeLong;
    const elapsedShort = txShort.settleTime - firstSettleTimeShort;
    const notionalLong = sizeAbs.mul(fillPriceLong).div(ONE);
    const notionalShort = sizeAbs.mul(fillPriceShort).div(ONE);

    // rate = charged / (notional * seconds) in D18
    const rateLong = chargedLong.mul(ONE).div(notionalLong).div(elapsedLong);
    const rateShort = chargedShort.mul(ONE).div(notionalShort).div(elapsedShort);

    // Both should be near the configured feePerSec
    assertBn.near(rateLong, feePerSec, bn(0.00000000000001));
    assertBn.near(rateShort, feePerSec, bn(0.00000000000001));

    // And near each other
    assertBn.near(rateLong, rateShort, bn(0.00000000000001));
  });
});
