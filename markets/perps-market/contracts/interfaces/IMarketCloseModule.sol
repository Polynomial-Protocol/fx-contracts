//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

interface IMarketCloseModule {
    struct MarketCloseRuntime {
        int128 sizeDelta;
        uint256 fillPrice;
        uint256 orderFees;
        uint256 settlementReward;
        uint256 totalFees;
        int256 pnl;
        int256 chargedAmount;
        uint256 chargedInterest;
        int256 accruedFunding;
        uint256 referralFees;
        uint256 feeCollectorFees;
    }

    /**
     * @notice Gets thrown when the caller is not authorized to close a position.
     * @param caller The address of the caller.
     */
    error UnauthorizedKeeper(address caller);

    /**
     * @notice Gets thrown when the rollover fee is not set for a market.
     * @param marketId The ID of the market.
     */
    error RolloverFeeNotSet(uint128 marketId);

    /**
     * @notice Gets thrown when the market is closed.
     * @param marketId The ID of the market.
     */
    error MarketAlreadyClosed(uint128 marketId);

    /**
     * @notice Gets fired when the rollover fee is set for a market.
     * @param marketId The ID of the market.
     * @param rolloverFee The rollover fee.
     */
    event RolloverFeeSet(uint128 indexed marketId, uint256 rolloverFee);

    /**
     * @notice Gets fired when a market is closed.
     * @param marketId The ID of the market.
     * @param closeTime The time the market was closed.
     * @param closePrice The price the market was closed at.
     */
    event MarketClosed(uint128 indexed marketId, uint256 closeTime, uint256 closePrice);

    /**
     * @notice Gets fired when a list of markets are opened.
     * @param marketId The ID of the market to open.
     */
    event MarketOpened(uint128 indexed marketId);

    /**
     * @notice Gets fired when the account positions are updated.
     * @param accountId The ID of the account.
     */
    event AccountPositionsUpdated(uint128 indexed accountId);

    /**
     * @notice Sets the rollover fee for a market.
     * @param marketId The ID of the market.
     * @param rolloverFee The rollover fee.
     */
    function setRolloverFee(uint128 marketId, uint256 rolloverFee) external;

    /**
     * @notice Gets the rollover fee for a market.
     * @param marketId The ID of the market.
     * @return rolloverFee The rollover fee.
     */
    function getRolloverFee(uint128 marketId) external view returns (uint256);

    /**
     * @notice Opens a list of markets.
     * @param marketIds The IDs of the markets to open.
     */
    function openMarkets(uint128[] calldata marketIds) external;

    /**
     * @notice Closes a list of markets.
     * @param marketIds The IDs of the markets to close.
     */
    function closeMarkets(uint128[] calldata marketIds) external;

    /**
     * @notice Closes a list of markets with timestamps.
     * @param marketIds The IDs of the markets to close.
     * @param timestamps The timestamps of the markets to close.
     */
    function closeMarketsWithTimestamps(
        uint128[] calldata marketIds,
        uint256[] calldata timestamps
    ) external;

    /**
     * @notice Closes a position.
     * @param accountId The ID of the account.
     * @param marketId The ID of the market.
     */
    function closePosition(uint128 accountId, uint128 marketId) external;

    /**
     * @notice Returns market close state for a market.
     * @param marketId The ID of the market.
     * @return isClosed Whether the market is closed.
     * @return openTime The time the market was opened.
     * @return closeTime The time the market was closed.
     * @return closePrice The price the market was closed at.
     */
    function getMarketCloseData(
        uint128 marketId
    )
        external
        view
        returns (bool isClosed, uint256 openTime, uint256 closeTime, uint256 closePrice);
}
