//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {OwnableStorage} from "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import {ISynthetixSystem} from "../interfaces/external/ISynthetixSystem.sol";
import {StrategyMarketFactory} from "../storage/StrategyMarketFactory.sol";
import {IStrategyMarketFactoryModule} from "../interfaces/IStrategyMarketFactoryModule.sol";
import {SafeCastI256} from "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import {IERC165} from "@synthetixio/core-contracts/contracts/interfaces/IERC165.sol";
import {IMarket} from "@synthetixio/main/contracts/interfaces/external/IMarket.sol";
import {ITokenModule} from "@synthetixio/core-modules/contracts/interfaces/ITokenModule.sol";

contract StrategyMarketFactoryModule is IStrategyMarketFactoryModule {
    using StrategyMarketFactory for StrategyMarketFactory.Data;
    using SafeCastI256 for int256;

    /**
     * @inheritdoc IStrategyMarketFactoryModule
     */
    function setSynthetix(ISynthetixSystem synthetix) external override {
        OwnableStorage.onlyOwner();
        StrategyMarketFactory.Data storage store = StrategyMarketFactory.load();

        store.synthetix = synthetix;
        (address usdTokenAddress, ) = synthetix.getAssociatedSystem("USDToken");
        store.usdToken = ITokenModule(usdTokenAddress);
        store.oracle = synthetix.getOracleManager();

        uint128 strategyMarketId = synthetix.registerMarket(address(this));
        store.strategyMarketId = strategyMarketId;

        emit SynthetixSystemSet(
            strategyMarketId,
            address(synthetix),
            usdTokenAddress,
            address(store.oracle)
        );
    }

    /**
     * @inheritdoc IStrategyMarketFactoryModule
     */
    function setMinCredit(uint256 minCreditD18) external override {
        OwnableStorage.onlyOwner();
        StrategyMarketFactory.load().minCreditD18 = minCreditD18;
        emit MinCreditSet(minCreditD18);
    }

    /**
     * @inheritdoc IMarket
     */
    function name(uint128) external view returns (string memory marketName) {
        return "Strategy Market";
    }

    /**
     * @inheritdoc IMarket
     */
    function minimumCredit(uint128) external view returns (uint256 lockedAmount) {
        return StrategyMarketFactory.load().minCreditD18;
    }

    /**
     * @inheritdoc IMarket
     */
    function reportedDebt(uint128) external view returns (uint256 reportedDebtAmount) {
        int256 netIssuance = StrategyMarketFactory.load().netIssuanceD18;
        return netIssuance < 0 ? 0 : netIssuance.toUint();
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165) returns (bool isSupported) {
        return
            interfaceId == type(IMarket).interfaceId ||
            interfaceId == this.supportsInterface.selector;
    }
}
