import { bn, bootstrapMarkets } from '../bootstrap';
import assertBn from '@synthetixio/core-utils/src/utils/assertions/assert-bignumber';
import { wei } from '@synthetixio/wei';
import { computeFees } from '../helpers';

const feeTiers = [
  { id: 0, makerDiscount: 0, takerDiscount: 0 }, // 0% / 0%
  { id: 1, makerDiscount: 1000, takerDiscount: 500 }, // 10% / 5%
  { id: 2, makerDiscount: 2000, takerDiscount: 1200 }, // 20% / 12%
  { id: 3, makerDiscount: 10000, takerDiscount: 10000 }, // 100% / 100%
];

describe('FeeTier', () => {
  const orderFees = {
    makerFee: wei(0.0003), // 3bps
    takerFee: wei(0.0008), // 8bps
  };
  const ethPrice = bn(1000);
  const ethMarketId = 25;

  const { systems, trader1 } = bootstrapMarkets({
    synthMarkets: [],
    perpsMarkets: [
      {
        requestedMarketId: ethMarketId,
        name: 'Ether',
        token: 'snxETH',
        price: ethPrice,
        // setting to 0 to avoid funding and p/d price change affecting pnl
        fundingParams: { skewScale: bn(0), maxFundingVelocity: bn(0) },
        orderFees: {
          makerFee: orderFees.makerFee.toBN(),
          takerFee: orderFees.takerFee.toBN(),
        },
      },
    ],
    traderAccountIds: [1, 2, 3],
  });

  before('create tiers', async () => {
    for (const tier of feeTiers) {
      await systems()
        .PerpsMarket.connect(trader1())
        .setFeeTier(tier.id, tier.makerDiscount, tier.takerDiscount);
    }
  });

  before('assign tiers to trading accounts', async () => {
    await systems().PerpsMarket.connect(trader1()).updateFeeTier(1, 1, '0x');
    await systems().PerpsMarket.connect(trader1()).updateFeeTier(2, 3, '0x');
  });

  describe('getFeeTier', () => {
    it('should return correct tier discounts', async () => {
      for (const tier of feeTiers) {
        const [makerDiscount, takerDiscount] = await systems()
          .PerpsMarket.connect(trader1())
          .getFeeTier(tier.id);
        assertBn.equal(makerDiscount, tier.makerDiscount);
        assertBn.equal(takerDiscount, tier.takerDiscount);
      }
    });
  });

  describe('getFeeTierId', () => {
    it('should return correct fee tier for trading accounts', async () => {
      assertBn.equal(await systems().PerpsMarket.connect(trader1()).getFeeTierId(1), 1);
      assertBn.equal(await systems().PerpsMarket.connect(trader1()).getFeeTierId(2), 3);
      assertBn.equal(await systems().PerpsMarket.connect(trader1()).getFeeTierId(3), 0);
    });
  });

  describe('computeOrderFees', () => {
    it('should return base fees for tier zero', async () => {
      const sizeDelta = bn(1);
      const tentativeFeesPaid = computeFees(wei(0), wei(sizeDelta), wei(ethPrice), orderFees);
      const [tentativeOrderFees] = await systems().PerpsMarket.computeOrderFeesWithPrice(
        3, // tier 0 account
        ethMarketId,
        sizeDelta,
        ethPrice
      );
      assertBn.equal(tentativeOrderFees, tentativeFeesPaid.perpsMarketFee);
    });

    it('should return discounted fees for non-zero tier', async () => {
      const sizeDelta = bn(1);
      const tentativeFeesPaidWithoutDiscount = computeFees(
        wei(0),
        wei(sizeDelta),
        wei(ethPrice),
        orderFees
      );
      const feeDiscount = 500; // 5% taker fee discount
      const tentativePerpsMarketFeesPaid = tentativeFeesPaidWithoutDiscount.perpsMarketFee
        .mul(10000 - feeDiscount)
        .div(10000);
      const [tentativeOrderFees] = await systems().PerpsMarket.computeOrderFeesWithPrice(
        1, // tier 1 account
        ethMarketId,
        sizeDelta,
        ethPrice
      );
      assertBn.equal(tentativeOrderFees, tentativePerpsMarketFeesPaid);
    });

    it('should return zero fees for tier 3', async () => {
      const sizeDelta = bn(1);
      const [tentativeOrderFees] = await systems().PerpsMarket.computeOrderFeesWithPrice(
        2, // tier 3 account
        ethMarketId,
        sizeDelta,
        ethPrice
      );
      assertBn.equal(tentativeOrderFees, 0);
    });
  });
});
