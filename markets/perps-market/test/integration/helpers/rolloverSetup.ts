import { ethers } from 'ethers';
import { Systems } from '../bootstrap';
import { MockGasPriceNode } from '../../../typechain-types/contracts/mocks/MockGasPriceNode';

export type ZeroFeesSetupArgs = {
  systems: () => Systems;
  owner: () => ethers.Signer;
  marketId: ethers.BigNumberish;
  strategyId: ethers.BigNumberish;
  keeperCostOracleNode?: () => MockGasPriceNode;
};

export const configureZeroFeesAndKeeperCosts = async ({
  systems,
  owner,
  marketId,
  strategyId,
  keeperCostOracleNode,
}: ZeroFeesSetupArgs) => {
  // zero maker/taker fees
  await systems().PerpsMarket.connect(owner()).setOrderFees(marketId, 0, 0);

  // set settlement reward to 0 for strategy
  const strategy = await systems().PerpsMarket.getSettlementStrategy(marketId, strategyId);
  await systems().PerpsMarket.connect(owner()).setSettlementStrategy(marketId, strategyId, {
    strategyType: strategy.strategyType,
    settlementDelay: strategy.settlementDelay,
    settlementWindowDuration: strategy.settlementWindowDuration,
    priceVerificationContract: strategy.priceVerificationContract,
    feedId: strategy.feedId,
    settlementReward: 0,
    disabled: strategy.disabled,
    commitmentPriceDelay: strategy.commitmentPriceDelay,
  });

  // zero keeper costs if available
  if (keeperCostOracleNode) {
    await keeperCostOracleNode().connect(owner()).setCosts(0, 0, 0);
  }

  // zero interest rate parameters to isolate rollover
  await systems().PerpsMarket.connect(owner()).setInterestRateParameters(0, 0, 0);
};
