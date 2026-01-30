//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

interface IUnsecuredCreditModule {
    struct MarketConfiguration {
        bool isWhitelisted;
        bool marketPaused;
        uint256 debtCapD18;
        uint256 ratePerSecondD18;
        uint256 epochLength;
        uint256 epochLimitD18;
    }

    error NotWhitelisted(uint128 marketId);
    error GlobalPaused();
    error MarketPaused(uint128 marketId);
    error InvalidMarket(uint128 marketId);
    error CapExceeded(uint256 requested, uint256 available);
    error EpochLimitExceeded(uint256 requested, uint256 remaining);
    error InvalidParameter(bytes32 parameter, string reason);
    error UnauthorizedMarket(address sender, uint128 marketId);

    event MarketConfigured(uint128 indexed marketId, MarketConfiguration config);
    event GlobalCapSet(uint256 capD18);
    event GlobalPauseSet(bool paused);
    event Borrowed(
        uint128 indexed marketId,
        uint256 amountD18,
        uint256 principalAfterD18,
        uint256 accruedAfterD18,
        address indexed target,
        address indexed sender
    );
    event Repaid(
        uint128 indexed marketId,
        uint256 amountD18,
        uint256 principalAfterD18,
        uint256 accruedAfterD18,
        uint256 badDebtAfterD18,
        address indexed payer,
        address indexed sender
    );

    function setGlobalCap(uint256 capD18) external;

    function setGlobalPause(bool paused) external;

    function configureMarket(uint128 marketId, MarketConfiguration calldata config) external;

    function accrue(uint128 marketId) external returns (uint256 accruedD18);

    function borrowUnsecured(
        uint128 marketId,
        address target,
        uint256 amountD18
    ) external returns (uint256 interestAccruedD18);

    function repayUnsecured(
        uint128 marketId,
        address from,
        uint256 amountD18
    )
        external
        returns (uint256 interestRepaidD18, uint256 principalRepaidD18, uint256 badDebtRepaidD18);

    function getMarketUnsecuredDebt(
        uint128 marketId
    ) external view returns (uint256 principalD18, uint256 accruedInterestD18, uint256 badDebtD18);

    function getAvailableToBorrow(uint128 marketId) external view returns (uint256 amountD18);
}
