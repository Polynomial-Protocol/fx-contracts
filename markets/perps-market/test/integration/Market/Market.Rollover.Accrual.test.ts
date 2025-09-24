import { ethers } from 'ethers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';
import { fastForward, advanceBlock } from '@synthetixio/core-utils/src/utils/hardhat/rpc';

describe('Market - Rollover - Accrual', () => {
  // Unique ids for this suite
  const REQ_MARKET_ID = 9021;
  const ACCOUNT_ID = 29021;

  const _PRICE = bn(1000);
  const ONE_HOUR = 3600;

  const { systems, perpsMarkets, provider, trader1, keeper, owner, keeperCostOracleNode } =
    bootstrapMarkets({
      synthMarkets: [],
      perpsMarkets: [
        {
          requestedMarketId: REQ_MARKET_ID,
          name: 'RolloverTest',
          token: 'snxROL',
          price: _PRICE,
          // no funding
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

  const feePerSec = bn(1).div(86400); // 1 per day in D18 over $1 notional

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

  let firstSettleTime: number;
  let settleTx: ethers.ContractTransaction; // eslint-disable-line @typescript-eslint/no-unused-vars
  before('open small long position', async () => {
    ({ settleTx, settleTime: firstSettleTime } = await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_ID,
      sizeDelta: bn(0.1),
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    }));
  });

  it('accrues expected rollover over one hour and charges on update', async () => {
    await fastForward(ONE_HOUR, provider());
    await advanceBlock(provider());

    const reduceTx = await openPosition({
      systems,
      provider,
      trader: trader1(),
      marketId,
      accountId: ACCOUNT_ID,
      sizeDelta: bn(-0.05), // reduce by 0.05
      settlementStrategyId: strategyId,
      price: _PRICE,
      keeper: keeper(),
    });

    // Parse events to get fillPrice and actual charged interest
    const receipt = await reduceTx.settleTx.wait();
    let fillPrice: ethers.BigNumber | undefined;
    let chargedInterest: ethers.BigNumber | undefined;
    for (const log of receipt.logs) {
      try {
        const parsed = systems().PerpsMarket.interface.parseLog(log);
        if (parsed.name === 'OrderSettled') {
          fillPrice = parsed.args.fillPrice as ethers.BigNumber;
        } else if (parsed.name === 'InterestCharged') {
          chargedInterest = parsed.args.interest as ethers.BigNumber;
        }
      } catch {
        /* ignore non-matching logs */
      }
    }

    if (!fillPrice || !chargedInterest) {
      throw new Error('Missing expected events in receipt');
    }

    const elapsed = reduceTx.settleTime - firstSettleTime; // seconds between settlements
    const ONE = bn(1);
    const sizeBefore = bn(0.1);
    const notional = sizeBefore.mul(fillPrice).div(ONE); // mulDecimal(size, price)
    const expected = notional.mul(feePerSec).div(ONE).mul(elapsed); // mulDecimal(notional, feePerSec) * seconds

    // Allow tiny rounding differences
    assertBn.near(chargedInterest, expected, bn(0.00000000000001));
  });
});
