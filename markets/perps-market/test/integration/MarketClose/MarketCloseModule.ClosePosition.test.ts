import { ethers } from 'ethers';
import assertEvent from '@synthetixio/core-utils/utils/assertions/assert-event';
import { bn, bootstrapMarkets } from '../bootstrap';
import { depositCollateral, openPosition } from '../helpers';
import { configureZeroFeesAndKeeperCosts } from '../helpers/rolloverSetup';

describe('MarketCloseModule - closePosition', () => {
  const REQ_MARKET_ID = 9030;
  const ACCOUNT_ID = 29030;

  const _PRICE = bn(1000);

  const { systems, perpsMarkets, provider, trader1, keeper, owner, signers, keeperCostOracleNode } =
    bootstrapMarkets({
      synthMarkets: [],
      perpsMarkets: [
        {
          requestedMarketId: REQ_MARKET_ID,
          name: 'ClosePos',
          token: 'snxCLOSE',
          price: _PRICE,
          fundingParams: { skewScale: bn(1_000_000), maxFundingVelocity: bn(0) },
          orderFees: { makerFee: bn(0), takerFee: bn(0) },
        },
      ],
      traderAccountIds: [ACCOUNT_ID],
    });

  let marketId: ethers.BigNumber;
  let strategyId: ethers.BigNumber;
  let allowedKeeper: ethers.Signer;

  before('identify market and actors', () => {
    marketId = perpsMarkets()[0].marketId();
    strategyId = perpsMarkets()[0].strategyId();
    allowedKeeper = signers()[8];
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

  const feePerSec = bn(1).div(86400);
  before('set rollover fee', async () => {
    await systems().PerpsMarket.connect(owner()).setRolloverFee(marketId, feePerSec);
  });

  before('allowlist keeper via referrerShare', async () => {
    await systems()
      .PerpsMarket.connect(owner())
      .updateReferrerShare(await allowedKeeper.getAddress(), bn(0.1));
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

  it('force closes position at latest price and emits events', async () => {
    // set latest pyth price for wrapper path used in closePosition
    await systems().MockPythERC7412Wrapper.setBenchmarkPrice(_PRICE);

    const tx = await systems()
      .PerpsMarket.connect(allowedKeeper)
      .closePosition(ACCOUNT_ID, marketId);

    // InterestCharged emitted with rollover since last baseline
    await assertEvent(tx, `InterestCharged(${ACCOUNT_ID},`, systems().PerpsMarket);

    // OrderSettled emitted; new size should be 0
    await assertEvent(tx, 'OrderSettled', systems().PerpsMarket);

    const sizeAfter = await systems().PerpsMarket.getOpenPositionSize(ACCOUNT_ID, marketId);
    // equals 0
    await assertEvent(tx, `OrderSettled(${marketId}, ${ACCOUNT_ID}`, systems().PerpsMarket);
    // direct size check
    if (!sizeAfter.isZero()) {
      throw new Error('position not fully closed');
    }
  });
});
