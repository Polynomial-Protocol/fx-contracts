//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IMarket} from "@synthetixio/main/contracts/interfaces/external/IMarket.sol";
import {ISynthetixSystem} from "./external/ISynthetixSystem.sol";

interface IYieldMarketFactoryModule is IMarket {
    /**
     * @notice Gets fired when the synthetix is set
     * @param strategyMarketId id of the strategy market
     * @param synthetix address of the synthetix core contract
     * @param usdTokenAddress address of the USDToken contract
     * @param oracleManager address of the Oracle Manager contract
     */
    event SynthetixSystemSet(
        uint128 strategyMarketId,
        address synthetix,
        address usdTokenAddress,
        address oracleManager
    );
    /**
     * @notice Gets fired when the minimum credit is set
     * @param minCreditD18 the new minimum credit for the strategy market.
     */
    event MinCreditSet(uint256 minCreditD18);
    /**
     * @notice Emitted when unsecured credit settings are updated.
     */
    event UnsecuredSettingsSet(address unsecuredCreditModule, bool useUnsecured);

    /**
     * @notice Sets the v3 synthetix core system.
     * @dev Pulls in the USDToken and oracle manager from the synthetix core system and sets those appropriately.
     * @param synthetix synthetix v3 core system address
     */
    function setSynthetix(ISynthetixSystem synthetix) external;

    /**
     * @notice Sets the minimum credit for the strategy market.
     * @param minCreditD18 the new minimum credit for the strategy market.
     */
    function setMinCredit(uint256 minCreditD18) external;

    /**
     * @notice Sets the unsecured credit module and toggle.
     * @param unsecuredCreditModule address of UnsecuredCreditModule (core)
     * @param useUnsecured whether to route borrow/repay via unsecured module
     */
    function setUnsecuredConfig(address unsecuredCreditModule, bool useUnsecured) external;
}
