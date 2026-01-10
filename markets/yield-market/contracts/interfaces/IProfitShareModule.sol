//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

interface IProfitShareModule {
    /**
     * @notice Thrown when the current allowance is insufficient.
     * @param current The current allowance.
     * @param required The required allowance.
     */
    error InsufficientAllowance(uint256 current, uint256 required);

    /**
     * @notice Thrown when the dev share is invalid.
     * @param newDevShare The new dev share.
     */
    error InvalidDevShare(uint256 newDevShare);

    /**
     * @notice Emitted when USD is borrowed from the strategy market.
     * @param to The address of the recipient of the borrowed USD.
     * @param amount The amount of USD borrowed.
     */
    event Borrowed(address indexed to, uint256 amount);
    /**
     * @notice Emitted when USD is repaid to the strategy market.
     * @param from The address of the sender of the repaid USD.
     * @param amount The amount of USD repaid.
     */
    event Repaid(address indexed from, uint256 amount);
    /**
     * @notice Emitted when profit is realized from the strategy market.
     * @param amount The amount of profit realized.
     * @param poolShare The share of the profit to the pool.
     * @param devShare The share of the profit to the dev.
     */
    event ProfitRealized(uint256 amount, uint256 poolShare, uint256 devShare);
    /**
     * @notice Emitted when the dev address is set.
     * @param devAddress The address of the dev.
     */
    event DevAddressSet(address indexed devAddress);

    /**
     * @notice Emitted when the dev share is set.
     * @param newDevShare The new dev share.
     */
    event DevShareSet(uint256 newDevShare);
    /**
     * @notice Emitted when USD is withdrawn for strategy deployment.
     */
    event StrategyUsdWithdrawn(address indexed to, uint256 amount);
    /**
     * @notice Emitted when collateral is deposited back from strategies.
     */
    event StrategyCollateralDeposited(address indexed collateralType, uint256 amount);

    /**
     * @notice Sets the dev address.
     * @param newDev The address of the new dev.
     */
    function setDevAddress(address newDev) external;

    /**
     * @notice Sets the dev share.
     * @param newDevShare The new dev share.
     */
    function setDevShare(uint256 newDevShare) external;
    /**
     * @notice Borrows USD from the strategy market.
     * @param to The address of the recipient of the borrowed USD.
     * @param amount The amount of USD borrowed.
     */
    function borrowUsd(address to, uint256 amount) external;
    /**
     * @notice Repays USD from a specific address.
     * @param from The address of the sender of the repaid USD.
     * @param amount The amount of USD repaid.
     */
    function repayUsdFrom(address from, uint256 amount) external;
    /**
     * @notice Repays USD to the strategy market using this contract's own USD balance.
     * @param amount The amount of USD repaid.
     */
    function repayUsd(uint256 amount) external;
    /**
     * @notice Realizes profit from the strategy market.
     * @dev Transfers 10% of the profit to the dev and 90% to the pool.
     * @param amount The amount of profit realized.
     */
    function realizeProfit(uint256 amount) external;

    /**
     * @notice Withdraw USD held by this market to a target strategy wallet.
     * @param to Recipient strategy address.
     * @param amount Amount of USD to transfer.
     */
    function withdrawStrategyUsd(address to, uint256 amount) external;

    /**
     * @notice Deposit collateral acquired by strategies into core on behalf of this market.
     * @param collateralType ERC20 collateral token.
     * @param amount Token amount (native decimals).
     */
    function depositStrategyCollateral(address collateralType, uint256 amount) external;
}
