//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {OwnableStorage} from "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import {ISynthetixSystem} from "../interfaces/external/ISynthetixSystem.sol";
import {YieldMarketFactory} from "../storage/YieldMarketFactory.sol";
import {IYieldMarketFactoryModule} from "../interfaces/IYieldMarketFactoryModule.sol";
import {SafeCastI256} from "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import {IERC165} from "@synthetixio/core-contracts/contracts/interfaces/IERC165.sol";
import {IMarket} from "@synthetixio/main/contracts/interfaces/external/IMarket.sol";
import {ITokenModule} from "@synthetixio/core-modules/contracts/interfaces/ITokenModule.sol";

contract YieldMarketFactoryModule is IYieldMarketFactoryModule {
    using YieldMarketFactory for YieldMarketFactory.Data;
    using SafeCastI256 for int256;

    /**
     * @inheritdoc IYieldMarketFactoryModule
     */
    function setSynthetix(ISynthetixSystem synthetix) external override {
        OwnableStorage.onlyOwner();
        YieldMarketFactory.Data storage store = YieldMarketFactory.load();

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
     * @inheritdoc IYieldMarketFactoryModule
     */
    function setMinCredit(uint256 minCreditD18) external override {
        OwnableStorage.onlyOwner();
        YieldMarketFactory.load().minCreditD18 = minCreditD18;
        emit MinCreditSet(minCreditD18);
    }

    /**
     * @inheritdoc IYieldMarketFactoryModule
     */
    function setUnsecuredConfig(bool useUnsecured) external override {
        OwnableStorage.onlyOwner();
        YieldMarketFactory.Data storage store = YieldMarketFactory.load();
        store.useUnsecured = useUnsecured;
        emit UnsecuredSettingsSet(useUnsecured);
    }

    /**
     * @inheritdoc IMarket
     */
    function name(uint128) external view returns (string memory marketName) {
        return "Yield Market";
    }

    /**
     * @inheritdoc IMarket
     */
    function minimumCredit(uint128) external view returns (uint256 lockedAmount) {
        return YieldMarketFactory.load().minCreditD18;
    }

    /**
     * @inheritdoc IMarket
     */
    function reportedDebt(uint128) external view returns (uint256 reportedDebtAmount) {
        YieldMarketFactory.Data storage store = YieldMarketFactory.load();

        uint256 unsecuredDebt;
        if (store.useUnsecured && address(store.synthetix) != address(0)) {
            (uint256 principalD18, uint256 accruedInterestD18, uint256 badDebtD18) = store
                .synthetix
                .getMarketUnsecuredDebt(store.strategyMarketId);
            unsecuredDebt = principalD18 + accruedInterestD18 + badDebtD18;
        }

        int256 netIssuance = store.netIssuanceD18;
        uint256 mintedDebt = netIssuance < 0 ? 0 : netIssuance.toUint();

        return mintedDebt + unsecuredDebt;
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
