//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "../storage/TimeLockCollateral.sol";

/**
 * @title Module for time-locking collateral in exchange for boost to collateralization ratio.
 * @notice Allows users to lock their collateral for fixed durations and receive enhanced collateral value.
 */
interface ITimeLockCollateralModule {
    /**
     * @notice Thrown when an account does not have sufficient available collateral for locking
     */
    error InsufficientCollateralForLock(uint128 accountId, address collateralType, uint256 amount);

    /**
     * @notice Thrown when trying to unlock a lock that doesn't exist or has already been unlocked
     */
    error InvalidLockId(uint256 lockId);

    /**
     * @notice Thrown when trying to unlock before the lock period has expired
     */
    error LockNotExpired(uint256 lockId, uint256 currentTime, uint256 unlockTime);

    /**
     * @notice Thrown when providing an invalid lock duration
     */
    error InvalidLockDuration(uint64 duration);

    /**
     * @notice Thrown when caller doesn't have permission to operate on the lock
     */
    error UnauthorizedLockOperation(uint256 lockId, address caller);

    /**
     * @notice Emitted when collateral is time-locked
     * @param accountId The account ID that locked collateral
     * @param collateralType The address of the collateral token
     * @param amount The amount of collateral locked (in system units, 18 decimals)
     * @param duration The lock duration in seconds
     * @param lockId The unique identifier for this lock
     * @param boostMultiplier The boost multiplier applied (basis points)
     */
    event CollateralTimeLocked(
        uint128 indexed accountId,
        address indexed collateralType,
        uint256 amount,
        uint64 duration,
        uint256 indexed lockId,
        uint256 boostMultiplier
    );

    /**
     * @notice Emitted when time-locked collateral is unlocked
     * @param accountId The account ID that unlocked collateral
     * @param collateralType The address of the collateral token
     * @param amount The amount of collateral unlocked (in system units, 18 decimals)
     * @param lockId The unique identifier for the unlocked lock
     */
    event CollateralTimeUnlocked(
        uint128 indexed accountId,
        address indexed collateralType,
        uint256 amount,
        uint256 indexed lockId
    );

    /**
     * @notice Locks collateral for a specified duration in exchange for a boost to its value
     * @dev The collateral will be locked from the account's available balance and cannot be withdrawn until the lock expires
     * @param accountId The account ID to lock collateral from
     * @param collateralType The address of the collateral token to lock
     * @param amount The amount of collateral to lock (in token's native decimals)
     * @param duration The duration to lock the collateral for (must be 90, 180, or 365 days)
     * @return lockId The unique identifier for the created lock
     *
     * Requirements:
     * - Caller must have ADMIN permission on the account
     * - Account must have sufficient available collateral
     * - Duration must be a valid option (90, 180, or 365 days)
     *
     * Emits a {CollateralTimeLocked} event.
     */
    function lockCollateral(
        uint128 accountId,
        address collateralType,
        uint256 amount,
        uint64 duration
    ) external returns (uint256 lockId);

    /**
     * @notice Unlocks previously time-locked collateral after the lock period has expired
     * @dev The unlocked collateral will be returned to the account's available balance
     * @param lockId The unique identifier of the lock to unlock
     * @return amount The amount of collateral unlocked (in token's native decimals)
     *
     * Requirements:
     * - Lock must exist and not already be unlocked
     * - Lock period must have expired
     * - Caller must have ADMIN permission on the account that owns the lock
     *
     * Emits a {CollateralTimeUnlocked} event.
     */
    function unlockCollateral(uint256 lockId) external returns (uint256 amount);

    /**
     * @notice Returns the total boosted collateral value for an account and collateral type
     * @dev This includes the boost applied to all active time-locked collateral
     * @param accountId The account ID to query
     * @param collateralType The address of the collateral token
     * @return boostedValue The total boosted value (in system units, 18 decimals)
     */
    function getBoostedCollateralValue(
        uint128 accountId,
        address collateralType
    ) external view returns (uint256 boostedValue);

    /**
     * @notice Returns detailed information about a specific time lock
     * @param lockId The unique identifier of the lock
     * @return lock The TimeLock struct containing all lock details
     */
    function getLockInfo(
        uint256 lockId
    ) external view returns (TimeLockCollateral.TimeLock memory lock);

    /**
     * @notice Returns all active lock IDs for a given account
     * @param accountId The account ID to query
     * @return lockIds Array of active lock IDs owned by the account
     */
    function getAccountActiveLocks(
        uint128 accountId
    ) external view returns (uint256[] memory lockIds);

    /**
     * @notice Returns the boost multiplier for a given lock duration
     * @param duration The lock duration in seconds
     * @return multiplier The boost multiplier (basis points, e.g., 11000 = 110%)
     */
    function getBoostMultiplier(uint64 duration) external pure returns (uint256 multiplier);

    /**
     * @notice Checks if a lock can be unlocked (i.e., if the lock period has expired)
     * @param lockId The unique identifier of the lock
     * @return canUnlock True if the lock can be unlocked, false otherwise
     */
    function canUnlockCollateral(uint256 lockId) external view returns (bool canUnlock);

    /**
     * @notice Returns the remaining time until a lock can be unlocked
     * @param lockId The unique identifier of the lock
     * @return remainingTime Time in seconds until unlock is available (0 if already unlockable)
     */
    function getRemainingLockTime(uint256 lockId) external view returns (uint256 remainingTime);

    /**
     * @notice Returns comprehensive collateral information for an account including time-locked and boosted values
     * @param accountId The account ID to query
     * @param collateralType The address of the collateral token
     * @return totalDeposited Total deposited collateral (regular + time-locked)
     * @return totalAvailable Available collateral for delegation/withdrawal
     * @return totalTimeLocked Total amount of collateral that is time-locked
     * @return totalBoostedValue Total boosted value from time-locked collateral
     */
    function getAccountCollateralSummary(
        uint128 accountId,
        address collateralType
    )
        external
        view
        returns (
            uint256 totalDeposited,
            uint256 totalAvailable,
            uint256 totalTimeLocked,
            uint256 totalBoostedValue
        );
}
