//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IAssociatedSystemsModule} from "@polynomial/core-modules/contracts/interfaces/IAssociatedSystemsModule.sol";
import {IMarketManagerModule} from "@polynomial/main/contracts/interfaces/IMarketManagerModule.sol";
import {IMarketCollateralModule} from "@polynomial/main/contracts/interfaces/IMarketCollateralModule.sol";
import {IUtilsModule} from "@polynomial/main/contracts/interfaces/IUtilsModule.sol";
import {ICollateralConfigurationModule} from "@polynomial/main/contracts/interfaces/ICollateralConfigurationModule.sol";

// solhint-disable-next-line no-empty-blocks
interface ISynthetixSystem is
    IAssociatedSystemsModule,
    IMarketCollateralModule,
    IMarketManagerModule,
    IUtilsModule,
    ICollateralConfigurationModule
{}
