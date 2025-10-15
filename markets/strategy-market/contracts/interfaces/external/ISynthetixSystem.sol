//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@synthetixio/core-modules/contracts/interfaces/IAssociatedSystemsModule.sol";
import "@synthetixio/main/contracts/interfaces/IMarketManagerModule.sol";
import "@synthetixio/main/contracts/interfaces/IMarketCollateralModule.sol";
import "@synthetixio/main/contracts/interfaces/IUtilsModule.sol";
import "@synthetixio/main/contracts/interfaces/IPoolModule.sol";

// solhint-disable no-empty-blocks
interface ISynthetixSystem is
    IAssociatedSystemsModule,
    IMarketCollateralModule,
    IMarketManagerModule,
    IPoolModule,
    IUtilsModule
{}
// solhint-enable no-empty-blocks
