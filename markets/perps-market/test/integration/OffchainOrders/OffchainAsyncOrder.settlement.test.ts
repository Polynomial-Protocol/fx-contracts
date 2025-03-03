import { BigNumber, ethers } from 'ethers';
import { DEFAULT_SETTLEMENT_STRATEGY, bn, bootstrapMarkets } from '../bootstrap';
import { fastForwardTo } from '@synthetixio/core-utils/utils/hardhat/rpc';
import { snapshotCheckpoint } from '@synthetixio/core-utils/utils/mocha/snapshot';
import { SynthMarkets } from '@synthetixio/spot-market/test/common';
import { DepositCollateralData, depositCollateral, settleOrder } from '../helpers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import assertEvent from '@synthetixio/core-utils/utils/assertions/assert-event';
import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
import assert from 'assert';
import { getTxTime } from '@synthetixio/core-utils/src/utils/hardhat/rpc';
import { wei } from '@synthetixio/wei';
import { createOrder, signOrder, Order } from '../helpers/offchainOrderHelper';

describe('Settlement Offchain Async Order test', () => {
  const {
    systems,
    perpsMarkets,
    synthMarkets,
    provider,
    trader1,
    trader2,
    keeper,
    owner,
    signers,
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
    traderAccountIds: [2, 3],
  });
  let ethMarketId: ethers.BigNumber;
  let btcSynth: SynthMarkets[number];
  let relayer: ethers.Signer;
  const relayerRatio = wei(0.3); // 30%

  const PERPS_COMMIT_OFFCHAIN_ORDER_PERMISSION_NAME = ethers.utils.formatBytes32String(
    'PERPS_COMMIT_OFFCHAIN_ORDER'
  );

  before('identify relayer', async () => {
    relayer = signers()[8];
  });

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
      ],
    },
  ];

  let order1: Order;

  before('identify actors, set fee collector, set relayer fees', async () => {
    ethMarketId = perpsMarkets()[0].marketId();
    btcSynth = synthMarkets()[0];

    await systems()
      .PerpsMarket.connect(owner())
      .setFeeCollector(systems().FeeCollectorMock.address);
    await systems()
      .PerpsMarket.connect(owner())
      .updateRelayerShare(await relayer.getAddress(), relayerRatio.toBN()); // 30%
    order1 = createOrder({
      accountId: testCase[0].collateralData[1].accountId(),
      marketId: ethMarketId,
      relayer: ethers.constants.AddressZero,
      amount: bn(100),
      price: bn(1000),
      expiration: Math.floor(Date.now() / 1000) + 1000,
      nonce: 9732849,
      isMaker: false,
      isShort: false,
      trackingCode: ethers.constants.HashZero,
    });
  });

  const restoreToCommit = snapshotCheckpoint(provider);

  describe('failures', () => {
    it('reverts if market id is incorrect', async () => {
      order1.marketId = BigNumber.from(69);
      order1.referrerOrRelayer = await relayer.getAddress();

      const signedOrder = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems().PerpsMarket.connect(trader1()).settleOffchainAsyncOrder(order1, signedOrder),
        'InvalidMarket("69")'
      );
    });

    it('reverts if account is invalid', async () => {
      order1.marketId = ethMarketId;
      order1.accountId = BigNumber.from(69);

      const signedOrder = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems().PerpsMarket.connect(trader1()).settleOffchainAsyncOrder(order1, signedOrder),
        'AccountNotFound("69")'
      );
    });

    // before('remove collateral', async () => {
    //   let margin = await systems().PerpsMarket.getAvailableMargin(2);
    //   console.log('margin', margin);
    //   // await systems().PerpsMarket.connect(trader1()).modifyCollateral(2, 2, margin.mul(-1));
    // });

    it(`reverts if account doesn't have margin`, async () => {
      order1.accountId = BigNumber.from(2);
      order1.referrerOrRelayer = await relayer.getAddress();

      const signedOrder = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems().PerpsMarket.connect(relayer).settleOffchainAsyncOrder(order1, signedOrder),
        'InsufficientMargin'
      );
    });

    after('add collateral', async () => {
      await depositCollateral(testCase[0].collateralData[0]);
      await depositCollateral(testCase[0].collateralData[1]);
    });
  });
});
