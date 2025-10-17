//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {ITokenModule} from "@synthetixio/core-modules/contracts/interfaces/ITokenModule.sol";
import {INodeModule} from "@synthetixio/oracle-manager/contracts/interfaces/INodeModule.sol";
import {ISynthetixSystem} from "../interfaces/external/ISynthetixSystem.sol";

library StrategyMarketFactory {
    bytes32 private constant _SLOT_STRATEGY_MARKET_FACTORY =
        keccak256(abi.encode("fi.polynomial.strategy-market.StrategyMarketFactory"));

    struct Data {
        /**
         * @dev snxUSD token address
         */
        ITokenModule usdToken;
        /**
         * @dev oracle manager address used for price feeds
         */
        INodeModule oracle;
        /**
         * @dev Synthetix core v3 proxy
         */
        ISynthetixSystem synthetix;
        /**
         * @dev global strategy market id
         */
        uint128 strategyMarketId;
        /**
         * @dev minimum credit for the strategy market
         */
        uint256 minCreditD18;
        /**
         * @dev net issuance for the strategy market
         */
        int256 netIssuanceD18;
    }

    function load() internal pure returns (Data storage strategyMarketFactory) {
        bytes32 s = _SLOT_STRATEGY_MARKET_FACTORY;
        assembly {
            strategyMarketFactory.slot := s
        }
    }
}
