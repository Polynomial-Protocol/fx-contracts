import { BigNumber, ethers } from 'ethers';
import { DEFAULT_SETTLEMENT_STRATEGY, bn, bootstrapMarkets } from '../bootstrap';
import { advanceBlock, fastForwardTo, getTime } from '@synthetixio/core-utils/utils/hardhat/rpc';
import { snapshotCheckpoint } from '@synthetixio/core-utils/utils/mocha/snapshot';
import { SynthMarkets } from '@synthetixio/spot-market/test/common';
import { DepositCollateralData, depositCollateral, signCancelOrderRequest } from '../helpers';
import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import assertEvent from '@synthetixio/core-utils/utils/assertions/assert-event';
import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
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
    trader3,
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
  const nonZeroLimitOrderMakerFee = bn(0.0002); // 2bps
  const nonZeroLimitOrderTakerFee = bn(0.0006); // 6bps

  const PERPS_COMMIT_OFFCHAIN_ORDER_PERMISSION_NAME = ethers.utils.formatBytes32String(
    'PERPS_COMMIT_OFFCHAIN_ORDER'
  );

  const PERPS_CANCEL_OFFCHAIN_ORDER_PERMISSION_NAME = ethers.utils.formatBytes32String(
    'PERPS_CANCEL_LIMIT_ORDER'
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
  let order2: Order;

  before('identify actors, set fee collector, set relayer fees', async () => {
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
    order1 = createOrder({
      accountId: 2,
      marketId: ethMarketId,
      relayer: ethers.constants.AddressZero,
      amount: bn(1),
      price: bn(1000),
      expiration: Math.floor(Date.now() / 1000) + 1000,
      nonce: 9732849,
      isMaker: false,
      isShort: false,
      trackingCode: ethers.constants.HashZero,
    });
    order2 = { ...order1 };
    order2.limitOrderMaker = true;
    order2.sizeDelta = bn(-1);
    order2.accountId = BigNumber.from(3);
  });

  const restoreToCommit = snapshotCheckpoint(provider);

  describe('failures', () => {
    it('reverts if market id is incorrect', async () => {
      order1.marketId = BigNumber.from(69);
      order1.referrerOrRelayer = await relayer.getAddress();

      order2.marketId = BigNumber.from(69);
      order2.referrerOrRelayer = await relayer.getAddress();

      const signedOrder1 = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      const signedOrder2 = await signOrder(
        order2,
        trader2() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems()
          .PerpsMarket.connect(trader1())
          .settleOffchainLimitOrder(order1, signedOrder1, order2, signedOrder2),
        'InvalidMarket("69")'
      );
    });

    it('reverts if account is invalid', async () => {
      order1.marketId = ethMarketId;
      order1.accountId = BigNumber.from(69);

      order2.marketId = ethMarketId;
      order2.accountId = BigNumber.from(69);

      const signedOrder1 = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      const signedOrder2 = await signOrder(
        order2,
        trader2() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems()
          .PerpsMarket.connect(trader1())
          .settleOffchainLimitOrder(order1, signedOrder1, order2, signedOrder2),
        'AccountNotFound("69")'
      );
    });

    it(`reverts if account doesn't have margin`, async () => {
      order1.accountId = BigNumber.from(2);
      order2.accountId = BigNumber.from(3);

      const signedOrder1 = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      const signedOrder2 = await signOrder(
        order2,
        trader2() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems()
          .PerpsMarket.connect(relayer)
          .settleOffchainLimitOrder(order2, signedOrder2, order1, signedOrder1),
        'InsufficientMargin'
      );
    });

    it(`reverts if signer is not authorized`, async () => {
      const signedOrder1 = await signOrder(
        order1,
        trader1() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      const signedOrder2 = await signOrder(
        order2,
        trader3() as ethers.Wallet,
        systems().PerpsMarket.address
      );

      await assertRevert(
        systems()
          .PerpsMarket.connect(relayer)
          .settleOffchainLimitOrder(order2, signedOrder2, order1, signedOrder1),
        `PermissionDenied("${3}", "${PERPS_COMMIT_OFFCHAIN_ORDER_PERMISSION_NAME}", "${await trader3().getAddress()}")`
      );
    });

    after('mine few blocks', async () => {
      await advanceBlock(provider());
      await advanceBlock(provider());
      await advanceBlock(provider());
    });

    describe(`Settlement of offchain limit order`, () => {
      let tx: ethers.ContractTransaction;
      let relayerAddress: string;

      before(restoreToCommit);

      before('add collateral', async () => {
        await depositCollateral(testCase[0].collateralData[0]);
        await depositCollateral(testCase[0].collateralData[1]);
      });

      it(`reverts if relayer is not authorized`, async () => {
        order1.referrerOrRelayer = await trader3().getAddress();
        order2.referrerOrRelayer = await trader3().getAddress();

        const signedOrder1 = await signOrder(
          order1,
          trader1() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        const signedOrder2 = await signOrder(
          order2,
          trader2() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        await assertRevert(
          systems()
            .PerpsMarket.connect(relayer)
            .settleOffchainLimitOrder(order2, signedOrder2, order1, signedOrder1),
          `LimitOrderRelayerInvalid("${await trader3().getAddress()}")`
        );
      });

      const restoreToSnapshot = snapshotCheckpoint(provider);

      it('settles the orders and emits the proper events', async () => {
        order1.referrerOrRelayer = await relayer.getAddress();
        order2.referrerOrRelayer = await relayer.getAddress();
        const signedShortOrder = await signOrder(
          order2,
          trader2() as ethers.Wallet,
          systems().PerpsMarket.address
        );
        const signedLongOrder = await signOrder(
          order1,
          trader1() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        const orderSettledEventsArgs = {
          trader1: [`${ethMarketId}`, `${order1.accountId}`, `${order1.nonce}`].join(', '),
          trader2: [`${ethMarketId}`, `${order2.accountId}`, `${order2.nonce}`].join(', '),
        };

        tx = await systems()
          .PerpsMarket.connect(relayer)
          .settleOffchainLimitOrder(order2, signedShortOrder, order1, signedLongOrder);

        await assertEvent(
          tx,
          `LimitOrderSettled(${orderSettledEventsArgs.trader1}`,
          systems().PerpsMarket
        );
        await assertEvent(
          tx,
          `LimitOrderSettled(${orderSettledEventsArgs.trader2}`,
          systems().PerpsMarket
        );
      });

      it('fails to cancel an already completed limit order', async () => {
        const cancelOrderStruct = { accountId: order1.accountId.toNumber(), nonce: order1.nonce };
        const signedCancelOrder = await signCancelOrderRequest(
          cancelOrderStruct,
          trader1() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        await assertRevert(
          systems()
            .PerpsMarket.connect(trader2())
            .functions[
              'cancelOffchainLimitOrder((uint128,uint256),(uint8,bytes32,bytes32))'
            ](cancelOrderStruct, signedCancelOrder),
          `LimitOrderAlreadyUsed(${order1.accountId}, ${order1.nonce})`
        );
      });

      it('successfully cancels a new limit order', async () => {
        const cancelOrderStruct = {
          accountId: order1.accountId.toNumber(),
          nonce: order1.nonce + 1,
        };
        const signedCancelOrder = await signCancelOrderRequest(
          cancelOrderStruct,
          trader1() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        tx = await systems()
          .PerpsMarket.connect(trader1())
          .functions[
            'cancelOffchainLimitOrder((uint128,uint256),(uint8,bytes32,bytes32))'
          ](cancelOrderStruct, signedCancelOrder);

        await assertEvent(
          tx,
          `LimitOrderCancelled(${cancelOrderStruct.accountId}, ${cancelOrderStruct.nonce})`,
          systems().PerpsMarket
        );
      });

      it('successfully cancels a new limit order by the account owner', async () => {
        const newNonceShortOrder = {
          accountId: order1.accountId.toNumber(),
          nonce: order1.nonce + 2,
        };
        tx = await systems()
          .PerpsMarket.connect(trader1())
          .functions[
            'cancelOffchainLimitOrder(uint128,uint256)'
          ](newNonceShortOrder.accountId, newNonceShortOrder.nonce);

        await assertEvent(
          tx,
          `LimitOrderCancelled(${newNonceShortOrder.accountId}, ${newNonceShortOrder.nonce})`,
          systems().PerpsMarket
        );
      });

      it('fails to cancel a new limit order by someone other than account owner without signature', async () => {
        const newNonceShortOrder = {
          accountId: order1.accountId.toNumber(),
          nonce: order1.nonce + 3,
        };
        await assertRevert(
          systems()
            .PerpsMarket.connect(trader2())
            .functions[
              'cancelOffchainLimitOrder(uint128,uint256)'
            ](newNonceShortOrder.accountId, newNonceShortOrder.nonce),
          `PermissionDenied(${newNonceShortOrder.accountId}, "${PERPS_CANCEL_OFFCHAIN_ORDER_PERMISSION_NAME}", "${await trader2().getAddress()}")`
        );
      });

      it('fails when the relayers are different for each order', async () => {
        order1.referrerOrRelayer = await trader2().getAddress();
        order2.referrerOrRelayer = await trader3().getAddress();
        order1.nonce = order1.nonce + 4;
        order2.nonce = order2.nonce + 4;

        const signedOrder1 = await signOrder(
          order1,
          trader1() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        const signedOrder2 = await signOrder(
          order2,
          trader2() as ethers.Wallet,
          systems().PerpsMarket.address
        );

        await assertRevert(
          systems()
            .PerpsMarket.connect(owner())
            .settleOffchainLimitOrder(order2, signedOrder2, order1, signedOrder1),
          `LimitOrderDifferentRelayer(${order2.referrerOrRelayer}, ${order1.referrerOrRelayer})`
        );
      });
    });
  });
});
