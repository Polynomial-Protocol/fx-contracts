//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IProfitShareModule} from "../interfaces/IProfitShareModule.sol";
import {ProfitShare} from "../storage/ProfitShare.sol";
import {StrategyMarketFactory} from "../storage/StrategyMarketFactory.sol";
import {OwnableStorage} from "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";

contract ProfitShareModule is IProfitShareModule {
    using ProfitShare for ProfitShare.Data;
    using StrategyMarketFactory for StrategyMarketFactory.Data;

    /**
     * @inheritdoc IProfitShareModule
     */
    function setDevAddress(address newDev) external override {
        OwnableStorage.onlyOwner();
        ProfitShare.load().devAddress = newDev;
        emit DevAddressSet(newDev);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function setDevShare(uint256 newDevShare) external override {
        OwnableStorage.onlyOwner();
        if (newDevShare > 5000) {
            revert InvalidDevShare(newDevShare);
        }
        ProfitShare.load().devShareD18 = newDevShare;
        emit DevShareSet(newDevShare);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function borrowUsd(address to, uint256 amount) external override {
        OwnableStorage.onlyOwner();

        StrategyMarketFactory.Data storage strategyMarketFactory = StrategyMarketFactory.load();

        // Mints snxUSD to the target and updates Core accounting
        strategyMarketFactory.synthetix.withdrawMarketUsd(
            strategyMarketFactory.strategyMarketId,
            to,
            amount
        );
        strategyMarketFactory.netIssuanceD18 += int256(amount);
        emit Borrowed(to, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function repayUsdFrom(address from, uint256 amount) external override {
        OwnableStorage.onlyOwner();

        StrategyMarketFactory.Data storage strategyMarketFactory = StrategyMarketFactory.load();

        // Burns snxUSD from `from` using allowance to this market and updates Core accounting
        strategyMarketFactory.synthetix.depositMarketUsd(
            strategyMarketFactory.strategyMarketId,
            from,
            amount
        );
        strategyMarketFactory.netIssuanceD18 -= int256(amount);

        strategyMarketFactory.synthetix.distributeDebtToPools(
            strategyMarketFactory.strategyMarketId,
            999999999
        );
        strategyMarketFactory.synthetix.rebalancePool(
            strategyMarketFactory.strategyMarketId,
            address(0)
        );
        emit Repaid(from, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function repayUsd(uint256 amount) external override {
        OwnableStorage.onlyOwner();

        StrategyMarketFactory.Data storage strategyMarketFactory = StrategyMarketFactory.load();

        strategyMarketFactory.synthetix.depositMarketUsd(
            strategyMarketFactory.strategyMarketId,
            address(this),
            amount
        );
        strategyMarketFactory.netIssuanceD18 -= int256(amount);

        strategyMarketFactory.synthetix.distributeDebtToPools(
            strategyMarketFactory.strategyMarketId,
            999999999
        );
        strategyMarketFactory.synthetix.rebalancePool(
            strategyMarketFactory.strategyMarketId,
            address(0)
        );
        emit Repaid(address(this), amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function realizeProfit(uint256 amount) external override {
        StrategyMarketFactory.Data storage strategyMarketFactory = StrategyMarketFactory.load();
        ProfitShare.Data storage profitShare = ProfitShare.load();

        uint256 devShare = (amount * profitShare.devShareD18) / 10000;
        uint256 poolShare = amount - devShare;

        strategyMarketFactory.usdToken.transfer(profitShare.devAddress, devShare);

        strategyMarketFactory.synthetix.depositMarketUsd(
            strategyMarketFactory.strategyMarketId,
            address(this),
            poolShare
        );
        strategyMarketFactory.netIssuanceD18 -= int256(poolShare);

        strategyMarketFactory.synthetix.distributeDebtToPools(
            strategyMarketFactory.strategyMarketId,
            999999999
        );
        strategyMarketFactory.synthetix.rebalancePool(
            strategyMarketFactory.strategyMarketId,
            address(0)
        );
        emit ProfitRealized(amount, poolShare, devShare);
    }
}
