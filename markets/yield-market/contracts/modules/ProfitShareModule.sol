//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IProfitShareModule} from "../interfaces/IProfitShareModule.sol";
import {ProfitShare} from "../storage/ProfitShare.sol";
import {YieldMarketFactory} from "../storage/YieldMarketFactory.sol";
import {OwnableStorage} from "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import {IERC20} from "@synthetixio/core-contracts/contracts/interfaces/IERC20.sol";
import {ERC2771Context} from "@synthetixio/core-contracts/contracts/utils/ERC2771Context.sol";
import {AccessError} from "@synthetixio/core-contracts/contracts/errors/AccessError.sol";
import {AddressError} from "@synthetixio/core-contracts/contracts/errors/AddressError.sol";

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
    function whitelistCaller(address caller) external override {
        OwnableStorage.onlyOwner();

        if (caller == address(0)) {
            revert AddressError.ZeroAddress();
        }

        YieldMarketFactory.load().whitelistedCallers[caller] = true;

        emit CallerWhitelisted(caller);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function removeWhitelistedCaller(address caller) external override {
        OwnableStorage.onlyOwner();

        if (caller == address(0)) {
            revert AddressError.ZeroAddress();
        }

        delete YieldMarketFactory.load().whitelistedCallers[caller];

        emit CallerRemovedFromWhitelist(caller);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function isWhitelistedCaller(
        address caller
    ) external view override returns (bool isWhitelisted) {
        return YieldMarketFactory.load().whitelistedCallers[caller];
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function borrowUsd(address to, uint256 amount) external override {
        validateCaller();

        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        if (strategyMarketFactory.useUnsecured) {
            strategyMarketFactory.synthetix.borrowUnsecured(
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
        emit Borrowed(to, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function repayUsdFrom(address from, uint256 amount) external override {
        validateCaller();

        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        if (strategyMarketFactory.useUnsecured) {
            strategyMarketFactory.synthetix.repayUnsecured(
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
        emit Repaid(from, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function repayUsd(uint256 amount) external override {
        validateCaller();

        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        if (strategyMarketFactory.useUnsecured) {
            uint256 current = strategyMarketFactory.usdToken.allowance(
                address(this),
                address(this)
            );
            if (current < amount) {
                strategyMarketFactory.usdToken.approve(address(this), amount);
            }
            strategyMarketFactory.synthetix.repayUnsecured(
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
        emit Repaid(address(this), amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function realizeProfit(uint256 amount) external override {
        validateCaller();
        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();
        ProfitShare.Data storage profitShare = ProfitShare.load();

        uint256 devShare = (amount * profitShare.devShareD18) / 10000;
        uint256 poolShare = amount - devShare;

        strategyMarketFactory.usdToken.transfer(profitShare.devAddress, devShare);

        _donateToPools(strategyMarketFactory, poolShare);
        emit ProfitRealized(amount, poolShare, devShare);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function donateProfit(uint256 amount) external override {
        validateCaller();
        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        _donateToPools(strategyMarketFactory, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function withdrawStrategyUsd(address to, uint256 amount) external override {
        validateCaller();
        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        strategyMarketFactory.usdToken.transfer(to, amount);
        emit StrategyUsdWithdrawn(to, amount);
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function depositStrategyCollateral(address collateralType, uint256 amount) external override {
        validateCaller();
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

    function _donateToPools(YieldMarketFactory.Data storage store, uint256 amount) private {
        if (amount == 0) {
            return;
        }

        uint256 repaidDebt = 0;
        uint256 donated = 0;

        if (store.useUnsecured) {
            (uint256 principalD18, uint256 accruedInterestD18, uint256 badDebtD18) = store
                .synthetix
                .getMarketUnsecuredDebt(store.strategyMarketId);
            uint256 totalDebt = principalD18 + accruedInterestD18 + badDebtD18;
            repaidDebt = amount > totalDebt ? totalDebt : amount;
            if (repaidDebt > 0) {
                _ensureUsdAllowance(store, repaidDebt);
                store.synthetix.repayUnsecured(store.strategyMarketId, address(this), repaidDebt);
            }
            donated = amount - repaidDebt;
        } else {
            donated = amount;
        }

        if (donated > 0) {
            _ensureUsdAllowance(store, donated);
            store.synthetix.donateMarketUsd(store.strategyMarketId, address(this), donated);
        }

        emit ProfitDonated(amount, repaidDebt, donated);
    }

    function _ensureUsdAllowance(YieldMarketFactory.Data storage store, uint256 amount) private {
        uint256 current = store.usdToken.allowance(address(this), address(this));
        if (current < amount) {
            store.usdToken.approve(address(this), amount);
        }
    }

    /**
     * @inheritdoc IProfitShareModule
     */
    function withdrawStrategyCollateral(
        address collateralType,
        address to,
        uint256 amount
    ) external override {
        validateCaller();
        YieldMarketFactory.Data storage strategyMarketFactory = YieldMarketFactory.load();

        strategyMarketFactory.synthetix.withdrawMarketCollateral(
            strategyMarketFactory.strategyMarketId,
            collateralType,
            amount
        );

        IERC20(collateralType).transfer(to, amount);
        emit StrategyCollateralWithdrawn(collateralType, to, amount);
    }

    function validateCaller() internal view {
        YieldMarketFactory.Data storage store = YieldMarketFactory.load();
        address msgSender = ERC2771Context._msgSender();
        bool isWhitelisted = store.whitelistedCallers[msgSender];
        if (!isWhitelisted) {
            revert AccessError.Unauthorized(msgSender);
        }
    }
}
