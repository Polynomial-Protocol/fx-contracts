import { bootstrapMarkets } from '../bootstrap';
import assertBn from '@synthetixio/core-utils/src/utils/assertions/assert-bignumber';

const feeTiers = [
  { id: 0, makerDiscount: 0, takerDiscount: 0 }, // 0% / 0%
  { id: 1, makerDiscount: 1000, takerDiscount: 500 }, // 10% / 5%
  { id: 2, makerDiscount: 2000, takerDiscount: 1200 }, // 20% / 12%
  { id: 3, makerDiscount: 3000, takerDiscount: 2000 }, // 30% / 20%
];

describe('FeeTier', () => {
  const { systems, trader1 } = bootstrapMarkets({
    synthMarkets: [],
    perpsMarkets: [],
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

  it('should return correct tier discounts', async () => {
    for (const tier of feeTiers) {
      const [makerDiscount, takerDiscount] = await systems()
        .PerpsMarket.connect(trader1())
        .getFeeTier(tier.id);
      assertBn.equal(makerDiscount, tier.makerDiscount);
      assertBn.equal(takerDiscount, tier.takerDiscount);
    }
  });

  it('should return correct fee tier for trading accounts', async () => {
    assertBn.equal(await systems().PerpsMarket.connect(trader1()).getFeeTierId(1), 1);
    assertBn.equal(await systems().PerpsMarket.connect(trader1()).getFeeTierId(2), 3);
    assertBn.equal(await systems().PerpsMarket.connect(trader1()).getFeeTierId(3), 0);
  });
});
