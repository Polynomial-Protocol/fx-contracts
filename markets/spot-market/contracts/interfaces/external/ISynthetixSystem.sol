//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@polynomial/core-modules/contracts/interfaces/IAssociatedSystemsModule.sol";
import "@polynomial/main/contracts/interfaces/IMarketManagerModule.sol";
import "@polynomial/main/contracts/interfaces/IMarketCollateralModule.sol";
import "@polynomial/main/contracts/interfaces/IUtilsModule.sol";

// solhint-disable no-empty-blocks
interface ISynthetixSystem is
    IAssociatedSystemsModule,
    IMarketCollateralModule,
    IMarketManagerModule,
    IUtilsModule
{}
// solhint-enable no-empty-blocks
