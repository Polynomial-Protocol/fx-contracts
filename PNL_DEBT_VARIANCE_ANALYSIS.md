# PnL vs Pool Debt Variance Analysis

## Question
Why doesn't the total PnL of all trades over the last 7 days match the total change in pool debt (sum of all vault debt), even after adjusting for user deposits and withdrawals?

## Answer: 5 Sources of Discrepancy

### 1. Interest & Rollover Fees Excluded from Market Debt

**Files:**
- `markets/perps-market/contracts/storage/PerpsMarket.sol` (lines 261-265, 420-426)
- `markets/perps-market/contracts/storage/Position.sol` (lines 70-119)
- `markets/perps-market/contracts/modules/PerpsMarketFactoryModule.sol` (lines 114-141)

The `debtCorrectionAccumulator` only captures `pricePnl + fundingPnl`:

```solidity
// PerpsMarket.sol:261-265
self.debtCorrectionAccumulator +=
    runtime.fundingDelta +
    runtime.notionalDelta +
    pricePnl +
    fundingPnl;
// NOTE: chargedInterest is NOT included
```

But Position PnL (Position.sol:94) includes interest:
```solidity
totalPnl = pricePnl + accruedFunding - chargedInterest;
```

And `chargedInterest` includes both:
- Interest on locked OI (utilization-based)
- Continuous rollover fee (per-dollar-per-second)

`marketDebt()` (PerpsMarket.sol:420-426) has no interest term:
```solidity
return (skew * price) + (skew * nextFunding) - debtCorrectionAccumulator;
```

The `reportedDebt` formula:
```solidity
reportedDebt = collateralValue + totalMarketDebt - totalAccountsDebt
```

When interest is charged: `totalAccountsDebt` increases but `totalMarketDebt` doesn't change. Interest implicitly benefits LPs through reduced `reportedDebt`, but isn't tracked as explicit debt.

### 2. Fees Withdrawn from Pool, Not in Market Debt

**Files:**
- `markets/perps-market/contracts/modules/AsyncOrderSettlementPythModule.sol` (lines 112, 165-192)
- `markets/perps-market/contracts/storage/GlobalPerpsMarketConfiguration.sol` (lines 177-207)

During settlement:
```solidity
// AsyncOrderSettlementPythModule.sol:112
chargedAmount = pnl - totalFees;  // fees subtracted before charging account
```

Then fees are separately withdrawn from the pool via `withdrawMarketUsd()`:
- Settlement/keeper rewards → keeper address
- Referral fees → referrer address
- Fee collector fees → fee collector contract

These are real USD outflows from the pool that don't appear in the trade PnL metric.

### 3. Liquidation Debt Wipe-Off

**Files:**
- `markets/perps-market/contracts/storage/PerpsAccount.sol` (lines 215-232, 574-634)
- `markets/perps-market/contracts/modules/LiquidationModule.sol` (lines 43-77)

When `flagForLiquidation()` is called:
```solidity
// PerpsAccount.sol:230
updateAccountDebt(self, -self.debt.toInt());  // debt zeroed
```

Account debt is wiped **before** positions are liquidated. Then `liquidatePosition()` updates `debtCorrectionAccumulator` via `updatePositionData()`, but `charge()` is **never called** during liquidation.

Any interest owed by the liquidated account is forgiven (vanishes from the system).

For partial liquidations, interest tracking resets:
```solidity
// PerpsAccount.sol:614-615
newPosition = Position.Data({
    latestInterestAccrued: 0,
    latestRolloverAccruedAt: 0,
    size: newPositionSize
});
```

### 4. Liquidation Keeper Rewards Withdrawn from Pool

**Files:**
- `markets/perps-market/contracts/modules/LiquidationModule.sol` (lines 337-354)

Keeper rewards during liquidation are withdrawn via `withdrawMarketUsd()`, reducing pool credit without a corresponding trade PnL entry.

### 5. Unrealized PnL of Open Positions

**Files:**
- `markets/perps-market/contracts/storage/PerpsMarket.sol` (lines 420-426)

`marketDebt()` continuously reflects unrealized PnL:
```solidity
marketDebt = (skew * price) + (skew * nextFunding) - debtCorrectionAccumulator
```

Pool debt fluctuates with every oracle price update. Trade PnL only captures realized PnL at settlement time.

## Summary

| Source | Effect on Discrepancy |
|--------|----------------------|
| Interest/rollover fees | Trade PnL shows loss but pool debt doesn't increase equivalently |
| Trading fees | Withdrawn from pool, absent from trade PnL |
| Liquidation debt wipe-off | Account debt zeroed, interest forgiven |
| Liquidation keeper rewards | Direct pool outflow, no trade PnL entry |
| Unrealized PnL changes | Pool debt changes continuously, trade PnL only on settlement |

## To Reconcile

To accurately compare trade PnL with pool debt changes:
1. Add back all fees withdrawn (settlement + referral + fee collector)
2. Add back all liquidation keeper rewards withdrawn
3. Account for interest/rollover fees charged to accounts
4. Account for debt written off during liquidations
5. Include the delta in unrealized PnL of positions still open at period boundaries
