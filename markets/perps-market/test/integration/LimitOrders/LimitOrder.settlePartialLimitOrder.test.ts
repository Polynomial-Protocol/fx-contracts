import { ethers } from 'ethers';
import { bn, bootstrapMarkets } from '../bootstrap';
import { snapshotCheckpoint } from '@synthetixio/core-utils/utils/mocha/snapshot';
import { SynthMarkets } from '@synthetixio/spot-market/test/common';
import { DepositCollateralData, depositCollateral, signOrder, Order } from '../helpers';
import { wei } from '@synthetixio/wei';
import assertEvent from '@synthetixio/core-utils/utils/assertions/assert-event';

describe('Settle Offchain Partial Limit Order tests', () => {
  const {
    systems,
    perpsMarkets,
    synthMarkets,
    provider,
    trader1,
    trader2,
    trader3,
    signers,
    owner,
  } = bootstrapMarkets({
    synthMarkets: [
      {
        name: 'Bitcoin',
        token: 'snxBTC',
        buyPrice: bn(10_000),
        sellPrice: bn(10_000),
      },
    ],
    perpsMarkets: [
      {
        requestedMarketId: 25,
        name: 'Ether',
        token: 'snxETH',
        price: bn(1000),
        fundingParams: { skewScale: bn(100_000), maxFundingVelocity: bn(0) },
      },
    ],
    traderAccountIds: [2, 3, 4],
  });
  let ethMarketId: ethers.BigNumber;
  let btcSynth: SynthMarkets[number];
  let shortOrder: Order;
  let longOrder1: Order;
  let longOrder2: Order;
  const price = bn(999.9995);
  const nonZeroLimitOrderMakerFee = bn(0.0002); // 2bps
  const nonZeroLimitOrderTakerFee = bn(0.0006); // 6bps
  let relayer: ethers.Signer;
  const relayerRatio = wei(0.3); // 30%

  before('identify relayer', async () => {
    relayer = signers()[8];
  });

  before('identify actors, set fee collector, set relayer fees, set market fees', async () => {
    ethMarketId = perpsMarkets()[0].marketId();
    btcSynth = synthMarkets()[0];
    await systems()
      .PerpsMarket.connect(owner())
      .setFeeCollector(systems().FeeCollectorMock.address);
    await systems()
      .PerpsMarket.connect(owner())
      .updateRelayerShare(await relayer.getAddress(), relayerRatio.toBN()); // 30%
    await systems()
      .PerpsMarket.connect(owner())
      .setLimitOrderFees(ethMarketId, nonZeroLimitOrderMakerFee, nonZeroLimitOrderTakerFee);
  });

  const restoreToCommit = snapshotCheckpoint(provider);

  const testCase: Array<{ name: string; collateralData: DepositCollateralData[] }> = [
    {
      name: 'snxUSD and snxBTC',
      collateralData: [
        {
          systems,
          trader: trader1,
          accountId: () => 2,
          collaterals: [
            {
              snxUSDAmount: () => bn(10_000_000),
            },
            {
              synthMarket: () => btcSynth,
              snxUSDAmount: () => bn(10_000_000),
            },
          ],
        },
        {
          systems,
          trader: trader2,
          accountId: () => 3,
          collaterals: [
            {
              snxUSDAmount: () => bn(10_000_000),
            },
            {
              synthMarket: () => btcSynth,
              snxUSDAmount: () => bn(10_000_000),
            },
          ],
        },
        {
          systems,
          trader: trader3,
          accountId: () => 4,
          collaterals: [
            {
              snxUSDAmount: () => bn(10_000_000),
            },
            {
              synthMarket: () => btcSynth,
              snxUSDAmount: () => bn(10_000_000),
            },
          ],
        },
      ],
    },
  ];

  before(restoreToCommit);

  before('add collateral', async () => {
    await depositCollateral(testCase[0].collateralData[0]);
    await depositCollateral(testCase[0].collateralData[1]);
    await depositCollateral(testCase[0].collateralData[2]);
  });

  before('creates the orders', async () => {
    shortOrder = {
      accountId: 2,
      marketId: ethMarketId,
      relayer: ethers.utils.getAddress(await relayer.getAddress()),
      amount: bn(-5),
      price,
      limitOrderMaker: true,
      expiration: Math.floor(Date.now() / 1000) + 1000,
      nonce: 9732849,
      allowPartialMatching: true,
      trackingCode: ethers.constants.HashZero,
    };
    longOrder1 = {
      ...shortOrder,
      accountId: 3,
      amount: bn(2),
      limitOrderMaker: false,
    };
    longOrder2 = {
      ...longOrder1,
      accountId: 4,
      amount: bn(6),
    };
  });

  const restoreToSnapshot = snapshotCheckpoint(provider);

  it('settles the orders partially and emits the proper events', async () => {
    const signedShortOrder = await signOrder(
      shortOrder,
      trader1() as ethers.Wallet,
      systems().PerpsMarket.address
    );
    const signedLongOrder1 = await signOrder(
      longOrder1,
      trader2() as ethers.Wallet,
      systems().PerpsMarket.address
    );
    const signedLongOrder2 = await signOrder(
      longOrder2,
      trader3() as ethers.Wallet,
      systems().PerpsMarket.address
    );
    const tx1 = await systems()
      .PerpsMarket.connect(owner())
      .settleLimitOrder(shortOrder, signedShortOrder, longOrder1, signedLongOrder1);

    const tx2 = await systems()
      .PerpsMarket.connect(owner())
      .settleLimitOrder(shortOrder, signedShortOrder, longOrder2, signedLongOrder2);

    const firstSettlementAmount = longOrder1.amount;
    const secondSettlementAmount = shortOrder.amount.add(longOrder1.amount).abs();

    const getLimitOrderFee = (amount: ethers.BigNumber, feeRatio: ethers.BigNumber) =>
      amount.mul(price).div(bn(1)).mul(feeRatio).div(bn(1)).toString();

    const limitOrderFeesShortTx1 = getLimitOrderFee(
      firstSettlementAmount,
      nonZeroLimitOrderMakerFee
    );
    const limitOrderFeesLongTx1 = getLimitOrderFee(
      firstSettlementAmount,
      nonZeroLimitOrderTakerFee
    );
    const limitOrderFeesShortTx2 = getLimitOrderFee(
      secondSettlementAmount,
      nonZeroLimitOrderMakerFee
    );
    const limitOrderFeesLongTx2 = getLimitOrderFee(
      secondSettlementAmount,
      nonZeroLimitOrderTakerFee
    );

    const orderSettledEventsArgsTx1 = {
      trader1: [
        `${ethMarketId}`,
        `${shortOrder.accountId}`,
        `${price}`,
        0,
        0,
        `${firstSettlementAmount.mul(-1)}`,
        `${firstSettlementAmount.mul(-1)}`,
        `${limitOrderFeesShortTx1}`,
        0,
        0,
        `"${shortOrder.trackingCode}"`,
        0,
      ].join(', '),
      trader2: [
        `${ethMarketId}`,
        `${longOrder1.accountId}`,
        `${price}`,
        0,
        0,
        `${firstSettlementAmount}`,
        `${firstSettlementAmount}`,
        `${limitOrderFeesLongTx1}`,
        0,
        0,
        `"${longOrder1.trackingCode}"`,
        0,
      ].join(', '),
    };
    const orderSettledEventsArgsTx2 = {
      trader1: [
        `${ethMarketId}`,
        `${shortOrder.accountId}`,
        `${price}`,
        0,
        0,
        `${secondSettlementAmount.mul(-1)}`,
        `${shortOrder.amount}`,
        `${limitOrderFeesShortTx2}`,
        0,
        0,
        `"${shortOrder.trackingCode}"`,
        0,
      ].join(', '),
      trader3: [
        `${ethMarketId}`,
        `${longOrder2.accountId}`,
        `${price}`,
        0,
        0,
        `${secondSettlementAmount}`,
        `${secondSettlementAmount}`,
        `${limitOrderFeesLongTx2}`,
        0,
        0,
        `"${longOrder2.trackingCode}"`,
        0,
      ].join(', '),
    };
    const marketUpdateEventsArgsTx1 = {
      trader1: [
        `${ethMarketId}`,
        `${price}`,
        `${firstSettlementAmount.mul(-1)}`,
        `${firstSettlementAmount}`,
        `${firstSettlementAmount.mul(-1)}`,
        0,
        0,
        0,
      ].join(', '),
      trader2: [
        `${ethMarketId}`,
        `${price}`,
        0,
        `${firstSettlementAmount.mul(2)}`,
        `${firstSettlementAmount}`,
        0,
        0,
        0,
      ].join(', '),
    };
    const marketUpdateEventsArgsTx2 = {
      trader1: [
        `${ethMarketId}`,
        `${price}`,
        `${secondSettlementAmount.mul(-1)}`,
        `${firstSettlementAmount.mul(2).add(secondSettlementAmount)}`,
        `${secondSettlementAmount.mul(-1)}`,
        0,
        0,
        0,
      ].join(', '),
      trader3: [
        `${ethMarketId}`,
        `${price}`,
        0,
        `${firstSettlementAmount.add(secondSettlementAmount).mul(2)}`,
        `${secondSettlementAmount}`,
        0,
        0,
        0,
      ].join(', '),
    };
    await assertEvent(
      tx1,
      `LimitOrderSettled(${orderSettledEventsArgsTx1.trader1})`,
      systems().PerpsMarket
    );
    await assertEvent(
      tx1,
      `LimitOrderSettled(${orderSettledEventsArgsTx1.trader2})`,
      systems().PerpsMarket
    );
    await assertEvent(
      tx1,
      `MarketUpdated(${marketUpdateEventsArgsTx1.trader1})`,
      systems().PerpsMarket
    );
    await assertEvent(
      tx1,
      `MarketUpdated(${marketUpdateEventsArgsTx1.trader2})`,
      systems().PerpsMarket
    );

    await assertEvent(
      tx2,
      `LimitOrderSettled(${orderSettledEventsArgsTx2.trader1})`,
      systems().PerpsMarket
    );
    await assertEvent(
      tx2,
      `LimitOrderSettled(${orderSettledEventsArgsTx2.trader3})`,
      systems().PerpsMarket
    );
    await assertEvent(
      tx2,
      `MarketUpdated(${marketUpdateEventsArgsTx2.trader1})`,
      systems().PerpsMarket
    );
    await assertEvent(
      tx2,
      `MarketUpdated(${marketUpdateEventsArgsTx2.trader3})`,
      systems().PerpsMarket
    );
  });
  after(restoreToSnapshot);
});
