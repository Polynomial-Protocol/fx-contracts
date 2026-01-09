import { BigNumber, ethers } from 'ethers';
import { DEFAULT_SETTLEMENT_STRATEGY, bn, bootstrapMarkets } from '../bootstrap';
import { advanceBlock, fastForwardTo, getTime } from '@synthetixio/core-utils/utils/hardhat/rpc';
import { snapshotCheckpoint } from '@synthetixio/core-utils/utils/mocha/snapshot';
import { SynthMarkets } from '@synthetixio/spot-market/test/common';
import { DepositCollateralData, depositCollateral } from '../helpers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import assertEvent from '@synthetixio/core-utils/utils/assertions/assert-event';
import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
import { wei } from '@synthetixio/wei';
import { createOrder, signOrder, Order } from '../helpers/offchainOrderHelper';

describe('Settlement Offchain Async Order test', () => {
  const { systems, perpsMarkets, synthMarkets, provider, trader1, trader2, owner, signers } =
    bootstrapMarkets({
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

  const testCases: Array<{ name: string; collateralData: DepositCollateralData }> = [
    {
      name: 'only snxUSD',
      collateralData: {
        systems,
        trader: trader1,
        accountId: () => 2,
        collaterals: [
          {
            snxUSDAmount: () => bn(10_000),
          },
        ],
      },
    },
    {
      name: 'only snxBTC',
      collateralData: {
        systems,
        trader: trader1,
        accountId: () => 2,
        collaterals: [
          {
            synthMarket: () => btcSynth,
            snxUSDAmount: () => bn(10_000),
          },
        ],
      },
    },
    {
      name: 'snxUSD and snxBTC',
      collateralData: {
        systems,
        trader: trader1,
        accountId: () => 2,
        collaterals: [
          {
            snxUSDAmount: () => bn(2), // less than needed to pay for settlementReward
          },
          {
            synthMarket: () => btcSynth,
            snxUSDAmount: () => bn(10_000),
          },
        ],
      },
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
      .updateReferrerShare(await relayer.getAddress(), relayerRatio.toBN()); // 30%
    order1 = createOrder({
      accountId: testCases[0].collateralData.accountId(),
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

    it(`reverts if signer is not authorized`, async () => {
      const signedOrder = await signOrder(
        order1,
        trader2() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems().PerpsMarket.connect(trader2()).settleOffchainAsyncOrder(order1, signedOrder),
        `PermissionDenied("${2}", "${PERPS_COMMIT_OFFCHAIN_ORDER_PERMISSION_NAME}", "${await trader2().getAddress()}")`
      );
    });

    it(`reverts if relayer is not authorized`, async () => {
      const signedOrder = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems().PerpsMarket.connect(trader2()).settleOffchainAsyncOrder(order1, signedOrder),
        `UnauthorizedRelayer("${await trader2().getAddress()}")`
      );
    });

    it(`reverts if size delta is zero`, async () => {
      order1.sizeDelta = bn(0);

      const signedOrder = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems().PerpsMarket.connect(relayer).settleOffchainAsyncOrder(order1, signedOrder),
        'ZeroSizeOrder()'
      );
    });

    it(`reverts if settlement strategy id is not existent`, async () => {
      order1.settlementStrategyId = 69;

      const signedOrder = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems().PerpsMarket.connect(relayer).settleOffchainAsyncOrder(order1, signedOrder),
        'InvalidSettlementStrategy("69")'
      );
    });

    it(`reverts if strategy id is disabled`, async () => {
      order1.settlementStrategyId = 0;
      await systems()
        .PerpsMarket.connect(owner())
        .setSettlementStrategyEnabled(ethMarketId, 0, false);

      const signedOrder = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems().PerpsMarket.connect(relayer).settleOffchainAsyncOrder(order1, signedOrder),
        'InvalidSettlementStrategy("0")'
      );
    });
  });

  for (let idx = 0; idx < testCases.length; idx++) {
    const testCase = testCases[idx];
    describe(`Using ${testCase.name} as collateral`, () => {
      let tx: ethers.ContractTransaction;
      let order: Order;
      let relayerAddress: string;

      before(restoreToCommit);

      before('add collateral', async () => {
        await depositCollateral(testCase.collateralData);
        relayerAddress = await relayer.getAddress();

        order = createOrder({
          accountId: testCases[0].collateralData.accountId(),
          marketId: ethMarketId,
          relayer: relayerAddress,
          amount: bn(1),
          price: bn(1000),
          expiration: Math.floor(Date.now() / 1000) + 1000,
          nonce: 9732849,
          isMaker: false,
          isShort: false,
          trackingCode: ethers.constants.HashZero,
        });
        order.acceptablePrice = bn(1050);
      });

      before('set price', async () => {
        await systems().MockPythERC7412Wrapper.setBenchmarkPrice(bn(1000));
      });

      const restoreToSettle = snapshotCheckpoint(provider);

      it('should revert before settlement time', async () => {
        order.timestamp = await getTime(provider());
        const signedOrder = await signOrder(
          order,
          trader1() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        await assertRevert(
          systems().PerpsMarket.connect(relayer).settleOffchainAsyncOrder(order, signedOrder),
          'SettlementWindowNotOpen'
        );
      });

      it('should settle after settlement time', async () => {
        order.timestamp = await getTime(provider());
        const signedOrder = await signOrder(
          order,
          trader1() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        await fastForwardTo(
          order.timestamp + DEFAULT_SETTLEMENT_STRATEGY.settlementDelay,
          provider()
        );

        tx = await systems()
          .PerpsMarket.connect(relayer)
          .settleOffchainAsyncOrder(order, signedOrder);
      });

      it('should emit event', async () => {
        await assertEvent(tx, 'OrderSettled', systems().PerpsMarket);
      });

      it('check position is live', async () => {
        const [pnl, funding, size] = await systems().PerpsMarket.getOpenPosition(2, ethMarketId);
        assertBn.equal(pnl, bn(-0.005));
        assertBn.equal(funding, bn(0));
        assertBn.equal(size, bn(1));
      });

      it('check position size', async () => {
        const size = await systems().PerpsMarket.getOpenPositionSize(2, ethMarketId);
        assertBn.equal(size, bn(1));
      });

      describe('can place new order', () => {
        it('should settle after settlement time', async () => {
          order.timestamp = await getTime(provider());
          const signedOrder = await signOrder(
            order,
            trader1() as ethers.Wallet,
            systems().PerpsMarket.address
          );

          await fastForwardTo(
            order.timestamp + DEFAULT_SETTLEMENT_STRATEGY.settlementDelay,
            provider()
          );

          tx = await systems()
            .PerpsMarket.connect(relayer)
            .settleOffchainAsyncOrder(order, signedOrder);
        });
      });

      after('mine few blocks', async () => {
        await advanceBlock(provider());
        await advanceBlock(provider());
        await advanceBlock(provider());
      });

      after('restore state', async () => {
        await restoreToSettle();
      });
    });
  }
});
