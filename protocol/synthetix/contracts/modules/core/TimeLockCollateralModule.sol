//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@synthetixio/core-contracts/contracts/errors/ParameterError.sol";
import "@synthetixio/core-contracts/contracts/utils/ERC2771Context.sol";
import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import "@synthetixio/core-contracts/contracts/interfaces/IERC20.sol";

import "../../interfaces/ITimeLockCollateralModule.sol";
import "../../storage/Account.sol";
import "../../storage/Collateral.sol";
import "../../storage/TimeLockCollateral.sol";
import "../../storage/CollateralConfiguration.sol";

/**
 * @title Module for time-locking collateral in exchange for boost.
 * @dev See ITimeLockCollateralModule.
 */
contract TimeLockCollateralModule is ITimeLockCollateralModule {
    using TimeLockCollateral for TimeLockCollateral.Data;
    using Account for Account.Data;
    using AccountRBAC for AccountRBAC.Data;
    using Collateral for Collateral.Data;
    using CollateralConfiguration for CollateralConfiguration.Data;
    using SafeCastU256 for uint256;
    using SafeCastU128 for uint128;
    using SafeCastU64 for uint64;

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function lockCollateral(
        uint128 accountId,
        address collateralType,
        uint256 amount,
        uint64 duration
    ) external override returns (uint256 lockId) {
        Account.Data storage account = Account.loadAccountAndValidatePermission(
            accountId,
            AccountRBAC._ADMIN_PERMISSION
        );

        CollateralConfiguration.collateralEnabled(collateralType);

        if (duration != 90 days && duration != 180 days && duration != 365 days) {
            revert InvalidLockDuration(duration);
        }

        if (amount == 0) {
            revert ParameterError.InvalidParameter("amount", "must be nonzero");
        }

        uint256 amountD18 = CollateralConfiguration.load(collateralType).convertTokenToSystemAmount(
            amount
        );

        uint256 availableCollateral = account
            .collaterals[collateralType]
            .amountAvailableForDelegationD18;

        if (amountD18 > availableCollateral) {
            revert InsufficientCollateralForLock(accountId, collateralType, amountD18);
        }

        account.collaterals[collateralType].decreaseAvailableCollateral(amountD18);

        TimeLockCollateral.Data storage timeLockStorage = TimeLockCollateral.load();
        lockId = timeLockStorage.createLock(accountId, collateralType, amountD18, duration);

        TimeLockCollateral.TimeLock memory lock = timeLockStorage.getLock(lockId);

        emit CollateralTimeLocked(
            accountId,
            collateralType,
            amountD18,
            duration,
            lockId,
            lock.boostMultiplier
        );
    }

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function unlockCollateral(uint256 lockId) external override returns (uint256 amount) {
        TimeLockCollateral.Data storage timeLockStorage = TimeLockCollateral.load();
        TimeLockCollateral.TimeLock memory lock = timeLockStorage.getLock(lockId);

        if (lock.accountId == 0) {
            revert InvalidLockId(lockId);
        }

        if (lock.unlocked) {
            revert InvalidLockId(lockId);
        }

        Account.loadAccountAndValidatePermission(lock.accountId, AccountRBAC._ADMIN_PERMISSION);

        uint256 unlockTime = lock.lockTimestamp + lock.lockDuration;
        if (block.timestamp < unlockTime) {
            revert LockNotExpired(lockId, block.timestamp, unlockTime);
        }

        uint256 amountD18 = timeLockStorage.unlockCollateral(lockId);

        Account.Data storage account = Account.load(lock.accountId);
        account.collaterals[lock.collateralType].increaseAvailableCollateral(amountD18);

        CollateralConfiguration.Data storage config = CollateralConfiguration.load(
            lock.collateralType
        );

        if (config.tokenAddress == address(0)) {
            revert InvalidLockId(lockId);
        }

        /// @dev this try-catch block assumes there is no malicious code in the token's fallback function
        try IERC20(config.tokenAddress).decimals() returns (uint8 decimals) {
            if (decimals == 18) {
                amount = amountD18;
            } else if (decimals < 18) {
                amount = (amountD18 * (10 ** decimals)) / 1e18;
            } else {
                amount = (amountD18 * (10 ** decimals)) / 1e18;
            }
        } catch {
            // if the token doesn't have a decimals function, assume it's 18 decimals
            amount = amountD18;
        }

        emit CollateralTimeUnlocked(lock.accountId, lock.collateralType, amountD18, lockId);
    }

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function getBoostedCollateralValue(
        uint128 accountId,
        address collateralType
    ) external view override returns (uint256 boostedValue) {
        TimeLockCollateral.Data storage timeLockStorage = TimeLockCollateral.load();
        return timeLockStorage.getBoostedCollateralValue(accountId, collateralType);
    }

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function getLockInfo(
        uint256 lockId
    ) external view override returns (TimeLockCollateral.TimeLock memory lock) {
        TimeLockCollateral.Data storage timeLockStorage = TimeLockCollateral.load();
        return timeLockStorage.getLock(lockId);
    }

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function getAccountActiveLocks(
        uint128 accountId
    ) external view override returns (uint256[] memory lockIds) {
        TimeLockCollateral.Data storage timeLockStorage = TimeLockCollateral.load();
        return timeLockStorage.getAccountLocks(accountId);
    }

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function getBoostMultiplier(
        uint64 duration
    ) external pure override returns (uint256 multiplier) {
        return TimeLockCollateral.getBoostMultiplier(duration);
    }

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function canUnlockCollateral(uint256 lockId) external view override returns (bool canUnlock) {
        TimeLockCollateral.Data storage timeLockStorage = TimeLockCollateral.load();
        TimeLockCollateral.TimeLock memory lock = timeLockStorage.getLock(lockId);

        if (lock.accountId == 0 || lock.unlocked) {
            return false;
        }

        return block.timestamp >= lock.lockTimestamp + lock.lockDuration;
    }

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function getRemainingLockTime(
        uint256 lockId
    ) external view override returns (uint256 remainingTime) {
        TimeLockCollateral.Data storage timeLockStorage = TimeLockCollateral.load();
        TimeLockCollateral.TimeLock memory lock = timeLockStorage.getLock(lockId);

        if (lock.accountId == 0 || lock.unlocked) {
            return 0;
        }

        uint256 unlockTime = lock.lockTimestamp + lock.lockDuration;
        if (block.timestamp >= unlockTime) {
            return 0;
        }

        return unlockTime - block.timestamp;
    }

    /**
     * @inheritdoc ITimeLockCollateralModule
     */
    function getAccountCollateralSummary(
        uint128 accountId,
        address collateralType
    )
        external
        view
        override
        returns (
            uint256 totalDeposited,
            uint256 totalAvailable,
            uint256 totalTimeLocked,
            uint256 totalBoostedValue
        )
    {
        Account.Data storage account = Account.load(accountId);
        TimeLockCollateral.Data storage timeLockStorage = TimeLockCollateral.load();

        (uint256 regularDeposited, , ) = account.getCollateralTotals(collateralType);
        totalAvailable = account.collaterals[collateralType].amountAvailableForDelegationD18;

        totalTimeLocked = timeLockStorage.getTotalTimeLocked(accountId, collateralType);

        totalDeposited = regularDeposited + totalTimeLocked;

        totalBoostedValue = timeLockStorage.getBoostedCollateralValue(accountId, collateralType);
    }
}
