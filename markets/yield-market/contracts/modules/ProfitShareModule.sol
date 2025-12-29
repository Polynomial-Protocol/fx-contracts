//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IProfitShareModule} from "../interfaces/IProfitShareModule.sol";
import {ProfitShare} from "../storage/ProfitShare.sol";
import {YieldMarketFactory} from "../storage/YieldMarketFactory.sol";
import {OwnableStorage} from "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import {IUnsecuredCreditModule} from "@synthetixio/main/contracts/interfaces/IUnsecuredCreditModule.sol";
import {IERC20} from "@synthetixio/core-contracts/contracts/interfaces/IERC20.sol";
import {ERC2771Context} from "@synthetixio/core-contracts/contracts/utils/ERC2771Context.sol";

contract ProfitShareModule is IProfitShareModule {
    using ProfitShare for ProfitShare.Data;
    using YieldMarketFactory for YieldMarketFactory.Data;

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

        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        if (strategyMarketFactory.useUnsecured) {
            IUnsecuredCreditModule(strategyMarketFactory.unsecuredCreditModule).borrowUnsecured(
                strategyMarketFactory.strategyMarketId,
                to,
                amount
            );
        } else {
            // Mints snxUSD to the target and updates Core accounting
            strategyMarketFactory.synthetix.withdrawMarketUsd(
                strategyMarketFactory.strategyMarketId,
                to,
                amount
            );
        }
        if (!strategyMarketFactory.useUnsecured) {
            // solhint-disable-next-line numcast/safe-cast
            strategyMarketFactory.netIssuanceD18 += int256(amount);
        }
        emit Borrowed(to, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function repayUsdFrom(address from, uint256 amount) external override {
        OwnableStorage.onlyOwner();

        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        if (strategyMarketFactory.useUnsecured) {
            IUnsecuredCreditModule(strategyMarketFactory.unsecuredCreditModule).repayUnsecured(
                strategyMarketFactory.strategyMarketId,
                from,
                amount
            );
        } else {
            // Burns snxUSD from `from` using allowance to this market and updates Core accounting
            strategyMarketFactory.synthetix.depositMarketUsd(
                strategyMarketFactory.strategyMarketId,
                from,
                amount
            );
        }
        if (!strategyMarketFactory.useUnsecured) {
            // solhint-disable-next-line numcast/safe-cast
            strategyMarketFactory.netIssuanceD18 -= int256(amount);
        }
        emit Repaid(from, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function repayUsd(uint256 amount) external override {
        OwnableStorage.onlyOwner();

        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        if (strategyMarketFactory.useUnsecured) {
            uint256 current = strategyMarketFactory.usdToken.allowance(
                address(this),
                address(this)
            );
            if (current < amount) {
                strategyMarketFactory.usdToken.approve(address(this), amount);
            }
            IUnsecuredCreditModule(strategyMarketFactory.unsecuredCreditModule).repayUnsecured(
                strategyMarketFactory.strategyMarketId,
                address(this),
                amount
            );
        } else {
            uint256 current = strategyMarketFactory.usdToken.allowance(
                address(this),
                address(this)
            );
            if (current < amount) {
                strategyMarketFactory.usdToken.approve(address(this), amount);
            }
            strategyMarketFactory.synthetix.depositMarketUsd(
                strategyMarketFactory.strategyMarketId,
                address(this),
                amount
            );
        }
        if (!strategyMarketFactory.useUnsecured) {
            // solhint-disable-next-line numcast/safe-cast
            strategyMarketFactory.netIssuanceD18 -= int256(amount);
        }
        emit Repaid(address(this), amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function realizeProfit(uint256 amount) external override {
        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();
        ProfitShare.Data storage profitShare = ProfitShare.load();

        uint256 devShare = (amount * profitShare.devShareD18) / 10000;
        uint256 poolShare = amount - devShare;

        strategyMarketFactory.usdToken.transfer(profitShare.devAddress, devShare);

        if (strategyMarketFactory.useUnsecured) {
            uint256 current = strategyMarketFactory.usdToken.allowance(
                address(this),
                address(this)
            );
            if (current < poolShare) {
                strategyMarketFactory.usdToken.approve(address(this), poolShare);
            }
            IUnsecuredCreditModule(strategyMarketFactory.unsecuredCreditModule).repayUnsecured(
                strategyMarketFactory.strategyMarketId,
                address(this),
                poolShare
            );
        } else {
            uint256 current = strategyMarketFactory.usdToken.allowance(
                address(this),
                address(this)
            );
            if (current < poolShare) {
                strategyMarketFactory.usdToken.approve(address(this), poolShare);
            }
            strategyMarketFactory.synthetix.depositMarketUsd(
                strategyMarketFactory.strategyMarketId,
                address(this),
                poolShare
            );
        }
        if (!strategyMarketFactory.useUnsecured) {
            // solhint-disable-next-line numcast/safe-cast
            strategyMarketFactory.netIssuanceD18 -= int256(poolShare);
        }
        emit ProfitRealized(amount, poolShare, devShare);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function withdrawStrategyUsd(address to, uint256 amount) external override {
        OwnableStorage.onlyOwner();
        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        strategyMarketFactory.usdToken.transfer(to, amount);
        emit StrategyUsdWithdrawn(to, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function depositStrategyCollateral(address collateralType, uint256 amount) external override {
        OwnableStorage.onlyOwner();
        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        IERC20 collateral = IERC20(collateralType);
        address caller = ERC2771Context._msgSender();
        uint256 currentAllowance = collateral.allowance(caller, address(this));
        if (currentAllowance < amount) {
            revert InsufficientAllowance(currentAllowance, amount);
        }
        // pull collateral from owner/manager into market contract
        collateral.transferFrom(caller, address(this), amount);

        if (
            collateral.allowance(address(this), address(strategyMarketFactory.synthetix)) < amount
        ) {
            collateral.approve(address(strategyMarketFactory.synthetix), amount);
        }

        strategyMarketFactory.synthetix.depositMarketCollateral(
            strategyMarketFactory.strategyMarketId,
            collateralType,
            amount
        );

        emit StrategyCollateralDeposited(collateralType, amount);
    }
}
