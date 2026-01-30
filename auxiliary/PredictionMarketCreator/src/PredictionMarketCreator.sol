//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IPerpsMarketProxy, SettlementStrategy} from "./interfaces/IPerpsMarketProxy.sol";
import "@synthetixio/core-contracts/contracts/utils/ERC2771Context.sol";

contract PredictionMarketCreator {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");
    bytes32 public constant MARKET_CONFIGURATOR_ROLE = keccak256("MARKET_CONFIGURATOR_ROLE");
    bytes32 public constant GLOBAL_CONFIGURATOR_ROLE = keccak256("GLOBAL_CONFIGURATOR_ROLE");

    IPerpsMarketProxy public immutable PERPS_MARKET_PROXY;

    mapping(bytes32 => mapping(address => bool)) private _roles;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event MarketCreated(uint128 indexed marketId, string name, string symbol, address creator);

    error AccessDenied(bytes32 role, address account);
    error ZeroAddress();

    modifier onlyRole(bytes32 role) {
        if (
            !hasRole(role, ERC2771Context._msgSender()) &&
            !hasRole(ADMIN_ROLE, ERC2771Context._msgSender())
        ) {
            revert AccessDenied(role, ERC2771Context._msgSender());
        }
        _;
    }

    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, ERC2771Context._msgSender())) {
            revert AccessDenied(ADMIN_ROLE, ERC2771Context._msgSender());
        }
        _;
    }

    constructor(address _perpsMarketProxy, address _admin) {
        if (_perpsMarketProxy == address(0) || _admin == address(0)) {
            revert ZeroAddress();
        }
        PERPS_MARKET_PROXY = IPerpsMarketProxy(_perpsMarketProxy);
        _roles[ADMIN_ROLE][_admin] = true;
        emit RoleGranted(ADMIN_ROLE, _admin, ERC2771Context._msgSender());
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(bytes32 role, address account) external onlyAdmin {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, ERC2771Context._msgSender());
        }
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, ERC2771Context._msgSender());
        }
    }

    function renounceRole(bytes32 role) external {
        if (_roles[role][ERC2771Context._msgSender()]) {
            _roles[role][ERC2771Context._msgSender()] = false;
            emit RoleRevoked(role, ERC2771Context._msgSender(), ERC2771Context._msgSender());
        }
    }

    function createMarket(
        uint128 requestedMarketId,
        string memory marketName,
        string memory marketSymbol
    ) external onlyRole(MARKET_CREATOR_ROLE) returns (uint128) {
        uint128 marketId = PERPS_MARKET_PROXY.createMarket(
            requestedMarketId,
            marketName,
            marketSymbol
        );
        emit MarketCreated(marketId, marketName, marketSymbol, ERC2771Context._msgSender());
        return marketId;
    }

    function addSettlementStrategy(
        uint128 marketId,
        SettlementStrategy memory strategy
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) returns (uint256) {
        return PERPS_MARKET_PROXY.addSettlementStrategy(marketId, strategy);
    }

    function setSettlementStrategy(
        uint128 marketId,
        uint256 strategyId,
        SettlementStrategy memory strategy
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setSettlementStrategy(marketId, strategyId, strategy);
    }

    function setSettlementStrategyEnabled(
        uint128 marketId,
        uint256 strategyId,
        bool enabled
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setSettlementStrategyEnabled(marketId, strategyId, enabled);
    }

    function setOrderFees(
        uint128 marketId,
        uint256 makerFeeRatio,
        uint256 takerFeeRatio
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setOrderFees(marketId, makerFeeRatio, takerFeeRatio);
    }

    function setLimitOrderFees(
        uint128 marketId,
        uint256 limitOrderMakerFeeRatio,
        uint256 limitOrderTakerFeeRatio
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setLimitOrderFees(
            marketId,
            limitOrderMakerFeeRatio,
            limitOrderTakerFeeRatio
        );
    }

    function updatePriceData(
        uint128 perpsMarketId,
        bytes32 feedId,
        uint256 strictStalenessTolerance
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.updatePriceData(perpsMarketId, feedId, strictStalenessTolerance);
    }

    function setMaxMarketSize(
        uint128 marketId,
        uint256 maxMarketSize
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setMaxMarketSize(marketId, maxMarketSize);
    }

    function setMaxMarketValue(
        uint128 marketId,
        uint256 maxMarketValue
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setMaxMarketValue(marketId, maxMarketValue);
    }

    function setFundingParameters(
        uint128 marketId,
        uint256 skewScale,
        uint256 maxFundingVelocity
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setFundingParameters(marketId, skewScale, maxFundingVelocity);
    }

    function setMaxLiquidationParameters(
        uint128 marketId,
        uint256 maxLiquidationLimitAccumulationMultiplier,
        uint256 maxSecondsInLiquidationWindow,
        uint256 maxLiquidationPd,
        address endorsedLiquidator
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setMaxLiquidationParameters(
            marketId,
            maxLiquidationLimitAccumulationMultiplier,
            maxSecondsInLiquidationWindow,
            maxLiquidationPd,
            endorsedLiquidator
        );
    }

    function setLiquidationParameters(
        uint128 marketId,
        uint256 initialMarginRatioD18,
        uint256 minimumInitialMarginRatioD18,
        uint256 maintenanceMarginScalarD18,
        uint256 flagRewardRatioD18,
        uint256 minimumPositionMargin
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setLiquidationParameters(
            marketId,
            initialMarginRatioD18,
            minimumInitialMarginRatioD18,
            maintenanceMarginScalarD18,
            flagRewardRatioD18,
            minimumPositionMargin
        );
    }

    function setLockedOiRatio(
        uint128 marketId,
        uint256 lockedOiRatioD18
    ) external onlyRole(MARKET_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setLockedOiRatio(marketId, lockedOiRatioD18);
    }

    function setKeeperRewardGuards(
        uint256 minKeeperRewardUsd,
        uint256 minKeeperProfitRatioD18,
        uint256 maxKeeperRewardUsd,
        uint256 maxKeeperScalingRatioD18
    ) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setKeeperRewardGuards(
            minKeeperRewardUsd,
            minKeeperProfitRatioD18,
            maxKeeperRewardUsd,
            maxKeeperScalingRatioD18
        );
    }

    function setFeeCollector(address feeCollector) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setFeeCollector(feeCollector);
    }

    function updateKeeperCostNodeId(
        bytes32 keeperCostNodeId
    ) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.updateKeeperCostNodeId(keeperCostNodeId);
    }

    function updateReferrerShare(
        address referrer,
        uint256 shareRatioD18
    ) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.updateReferrerShare(referrer, shareRatioD18);
    }

    function setPerAccountCaps(
        uint128 maxPositionsPerAccount,
        uint128 maxCollateralsPerAccount
    ) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setPerAccountCaps(maxPositionsPerAccount, maxCollateralsPerAccount);
    }

    function setInterestRateParameters(
        uint128 lowUtilizationInterestRateGradient,
        uint128 interestRateGradientBreakpoint,
        uint128 highUtilizationInterestRateGradient
    ) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setInterestRateParameters(
            lowUtilizationInterestRateGradient,
            interestRateGradientBreakpoint,
            highUtilizationInterestRateGradient
        );
    }

    function setCollateralConfiguration(
        uint128 collateralId,
        uint256 maxCollateralAmount,
        uint256 upperLimitDiscount,
        uint256 lowerLimitDiscount,
        uint256 discountScalar
    ) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setCollateralConfiguration(
            collateralId,
            maxCollateralAmount,
            upperLimitDiscount,
            lowerLimitDiscount,
            discountScalar
        );
    }

    function setCollateralLiquidateRewardRatio(
        uint128 collateralLiquidateRewardRatioD18
    ) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.setCollateralLiquidateRewardRatio(collateralLiquidateRewardRatioD18);
    }

    function registerDistributor(
        address token,
        address distributor,
        uint128 collateralId,
        address[] calldata poolDelegatedCollateralTypes
    ) external onlyRole(GLOBAL_CONFIGURATOR_ROLE) {
        PERPS_MARKET_PROXY.registerDistributor(
            token,
            distributor,
            collateralId,
            poolDelegatedCollateralTypes
        );
    }

    function setFeatureFlagAllowAll(bytes32 feature, bool allowAll) external onlyAdmin {
        PERPS_MARKET_PROXY.setFeatureFlagAllowAll(feature, allowAll);
    }

    function addToFeatureFlagAllowlist(bytes32 feature, address account) external onlyAdmin {
        PERPS_MARKET_PROXY.addToFeatureFlagAllowlist(feature, account);
    }

    function removeFromFeatureFlagAllowlist(bytes32 feature, address account) external onlyAdmin {
        PERPS_MARKET_PROXY.removeFromFeatureFlagAllowlist(feature, account);
    }

    function nominateNewOwner(address newNominatedOwner) external onlyAdmin {
        PERPS_MARKET_PROXY.nominateNewOwner(newNominatedOwner);
    }

    function acceptOwnership() external onlyAdmin {
        PERPS_MARKET_PROXY.acceptOwnership();
    }
}
