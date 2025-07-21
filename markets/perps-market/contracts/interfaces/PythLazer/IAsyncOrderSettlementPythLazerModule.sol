//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {Position} from "../../storage/Position.sol";
import {MarketUpdate} from "../../storage/MarketUpdate.sol";

interface IAsyncOrderSettlementPythLazerModule {
    // only used due to stack too deep during settlement
    struct SettleOrderRuntime {
        uint128 marketId;
        uint128 accountId;
        int128 sizeDelta;
        int256 pnl;
        uint256 chargedInterest;
        int256 accruedFunding;
        uint256 settlementReward;
        uint256 fillPrice;
        uint256 totalFees;
        uint256 referralFees;
        uint256 feeCollectorFees;
        Position.Data newPosition;
        MarketUpdate.Data updateData;
        uint256 synthDeductionIterator;
        uint128[] deductedSynthIds;
        uint256[] deductedAmount;
        int256 chargedAmount;
        uint256 newAccountDebt;
    }
    /**
     * @notice Settles an offchain order using the offchain retrieved data from pyth.
     * @param accountId The account id to settle the order
     */

    function settleOrderPythLazer(uint128 accountId) external;
}
