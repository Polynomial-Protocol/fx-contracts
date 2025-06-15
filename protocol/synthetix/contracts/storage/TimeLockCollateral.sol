//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import "./CollateralLock.sol";

/**
 * @title Storage for time-locked collateral with boost functionality
 */
library TimeLockCollateral {
    using SafeCastU256 for uint256;
    using SafeCastU128 for uint128;
    using SafeCastU64 for uint64;

    struct TimeLock {
        /**
         * @dev Unique identifier for the time lock
         */
        uint256 lockId;
        /**
         * @dev The account ID that owns this lock
         */
        uint128 accountId;
        /**
         * @dev The type of collateral being locked
         */
        address collateralType;
        /**
         * @dev The amount of collateral locked (in system units, 18 decimals)
         */
        uint256 amountD18;
        /**
         * @dev The timestamp when the lock was created
         */
        uint64 lockTimestamp;
        /**
         * @dev The duration of the lock in seconds
         */
        uint64 lockDuration;
        /**
         * @dev The boost multiplier for this lock (basis points, e.g., 1100 = 110%)
         */
        uint256 boostMultiplier;
        /**
         * @dev Whether the lock has been unlocked
         */
        bool unlocked;
    }

    struct Data {
        /**
         * @dev Counter for generating unique lock IDs
         */
        uint256 nextLockId;
        /**
         * @dev Mapping from lock ID to TimeLock data
         */
        mapping(uint256 => TimeLock) locks;
        /**
         * @dev Mapping from account ID to array of lock IDs owned by that account
         */
        mapping(uint128 => uint256[]) accountLocks;
        /**
         * @dev Mapping from account ID and collateral type to total boosted value
         */
        mapping(uint128 => mapping(address => uint256)) accountBoostedValue;
    }

    /**
     * @dev Returns the singleton storage instance
     */
    function load() internal pure returns (Data storage store) {
        bytes32 s = keccak256(abi.encode("io.synthetix.synthetix.TimeLockCollateral"));
        assembly {
            store.slot := s
        }
    }

    /**
     * @dev Creates a new time lock
     */
    function createLock(
        Data storage self,
        uint128 accountId,
        address collateralType,
        uint256 amountD18,
        uint64 duration
    ) internal returns (uint256 lockId) {
        lockId = ++self.nextLockId;

        uint256 boostMultiplier = getBoostMultiplier(duration);

        TimeLock storage newLock = self.locks[lockId];
        newLock.lockId = lockId;
        newLock.accountId = accountId;
        newLock.collateralType = collateralType;
        newLock.amountD18 = amountD18;
        newLock.lockTimestamp = block.timestamp.to64();
        newLock.lockDuration = duration;
        newLock.boostMultiplier = boostMultiplier;
        newLock.unlocked = false;

        // Add to account's locks
        self.accountLocks[accountId].push(lockId);

        // Update boosted value
        uint256 boostedAmount = (amountD18 * boostMultiplier) / 10000;
        self.accountBoostedValue[accountId][collateralType] += boostedAmount;
    }

    /**
     * @dev Unlocks a time lock if the duration has passed
     */
    function unlockCollateral(
        Data storage self,
        uint256 lockId
    ) internal returns (uint256 amountD18) {
        TimeLock storage lock = self.locks[lockId];
        require(!lock.unlocked, "Lock already unlocked");
        require(
            block.timestamp >= lock.lockTimestamp + lock.lockDuration,
            "Lock period not yet expired"
        );

        lock.unlocked = true;
        amountD18 = lock.amountD18;

        // Update boosted value
        uint256 boostedAmount = (amountD18 * lock.boostMultiplier) / 10000;
        self.accountBoostedValue[lock.accountId][lock.collateralType] -= boostedAmount;
    }

    /**
     * @dev Returns the boost multiplier based on duration
     * 3 months (90 days) = 10500 (105% in basis points)
     * 6 months (180 days) = 10750 (107.5% in basis points)
     * 12 months (365 days) = 11000 (110% in basis points)
     */
    function getBoostMultiplier(uint64 duration) internal pure returns (uint256) {
        if (duration >= 365 days) {
            return 11000; // 110% (basis points)
        } else if (duration >= 180 days) {
            return 10750; // 107.5% (basis points)
        } else if (duration >= 90 days) {
            return 10500; // 105% (basis points)
        }
        revert("Invalid lock duration");
    }

    /**
     * @dev Gets the total boosted collateral value for an account and collateral type
     */
    function getBoostedCollateralValue(
        Data storage self,
        uint128 accountId,
        address collateralType
    ) internal view returns (uint256) {
        return self.accountBoostedValue[accountId][collateralType];
    }

    /**
     * @dev Gets a time lock by ID
     */
    function getLock(Data storage self, uint256 lockId) internal view returns (TimeLock memory) {
        return self.locks[lockId];
    }

    /**
     * @dev Gets all active lock IDs for an account
     */
    function getAccountLocks(
        Data storage self,
        uint128 accountId
    ) internal view returns (uint256[] memory activeLockIds) {
        uint256[] storage allLocks = self.accountLocks[accountId];
        uint256 activeCount = 0;

        // Count active locks
        for (uint256 i = 0; i < allLocks.length; i++) {
            if (!self.locks[allLocks[i]].unlocked) {
                activeCount++;
            }
        }

        // Create array of active lock IDs
        activeLockIds = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allLocks.length; i++) {
            if (!self.locks[allLocks[i]].unlocked) {
                activeLockIds[index] = allLocks[i];
                index++;
            }
        }
    }

    /**
     * @dev Gets the total amount of time-locked collateral for an account and collateral type
     */
    function getTotalTimeLocked(
        Data storage self,
        uint128 accountId,
        address collateralType
    ) internal view returns (uint256 totalAmount) {
        uint256[] storage allLocks = self.accountLocks[accountId];
        totalAmount = 0;

        for (uint256 i = 0; i < allLocks.length; i++) {
            TimeLock storage lock = self.locks[allLocks[i]];
            if (lock.collateralType == collateralType && !lock.unlocked) {
                totalAmount += lock.amountD18;
            }
        }
    }
}
