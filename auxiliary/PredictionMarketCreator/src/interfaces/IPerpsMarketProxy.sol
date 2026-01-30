//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

struct SettlementStrategy {
    uint8 strategyType;
    uint256 settlementDelay;
    uint256 settlementWindowDuration;
    address priceVerificationContract;
    bytes32 feedId;
    uint256 settlementReward;
    bool disabled;
    uint256 commitmentPriceDelay;
}

interface IPerpsMarketProxy {
    function owner() external view returns (address);

    function nominateNewOwner(address newNominatedOwner) external;

    function acceptOwnership() external;

    function createMarket(
        uint128 requestedMarketId,
        string memory marketName,
        string memory marketSymbol
    ) external returns (uint128);

    function addSettlementStrategy(
        uint128 marketId,
        SettlementStrategy memory strategy
    ) external returns (uint256 strategyId);

    function setSettlementStrategy(
        uint128 marketId,
        uint256 strategyId,
        SettlementStrategy memory strategy
    ) external;

    function setSettlementStrategyEnabled(
        uint128 marketId,
        uint256 strategyId,
        bool enabled
    ) external;

    function setOrderFees(uint128 marketId, uint256 makerFeeRatio, uint256 takerFeeRatio) external;

    function setLimitOrderFees(
        uint128 marketId,
        uint256 limitOrderMakerFeeRatio,
        uint256 limitOrderTakerFeeRatio
    ) external;

    function updatePriceData(
        uint128 perpsMarketId,
        bytes32 feedId,
        uint256 strictStalenessTolerance
    ) external;

    function setMaxMarketSize(uint128 marketId, uint256 maxMarketSize) external;

    function setMaxMarketValue(uint128 marketId, uint256 maxMarketValue) external;

    function setFundingParameters(
        uint128 marketId,
        uint256 skewScale,
        uint256 maxFundingVelocity
    ) external;

    function setMaxLiquidationParameters(
        uint128 marketId,
        uint256 maxLiquidationLimitAccumulationMultiplier,
        uint256 maxSecondsInLiquidationWindow,
        uint256 maxLiquidationPd,
        address endorsedLiquidator
    ) external;

    function setLiquidationParameters(
        uint128 marketId,
        uint256 initialMarginRatioD18,
        uint256 minimumInitialMarginRatioD18,
        uint256 maintenanceMarginScalarD18,
        uint256 flagRewardRatioD18,
        uint256 minimumPositionMargin
    ) external;

    function setLockedOiRatio(uint128 marketId, uint256 lockedOiRatioD18) external;

    function setKeeperRewardGuards(
        uint256 minKeeperRewardUsd,
        uint256 minKeeperProfitRatioD18,
        uint256 maxKeeperRewardUsd,
        uint256 maxKeeperScalingRatioD18
    ) external;

    function setFeeCollector(address feeCollector) external;

    function updateKeeperCostNodeId(bytes32 keeperCostNodeId) external;

    function updateReferrerShare(address referrer, uint256 shareRatioD18) external;

    function setPerAccountCaps(
        uint128 maxPositionsPerAccount,
        uint128 maxCollateralsPerAccount
    ) external;

    function setInterestRateParameters(
        uint128 lowUtilizationInterestRateGradient,
        uint128 interestRateGradientBreakpoint,
        uint128 highUtilizationInterestRateGradient
    ) external;

    function setCollateralConfiguration(
        uint128 collateralId,
        uint256 maxCollateralAmount,
        uint256 upperLimitDiscount,
        uint256 lowerLimitDiscount,
        uint256 discountScalar
    ) external;

    function setCollateralLiquidateRewardRatio(uint128 collateralLiquidateRewardRatioD18) external;

    function registerDistributor(
        address token,
        address distributor,
        uint128 collateralId,
        address[] calldata poolDelegatedCollateralTypes
    ) external;

    function setFeatureFlagAllowAll(bytes32 feature, bool allowAll) external;

    function addToFeatureFlagAllowlist(bytes32 feature, address account) external;

    function removeFromFeatureFlagAllowlist(bytes32 feature, address account) external;
}
