//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {OffchainOrder} from "../../storage/OffchainOrder.sol";

interface IOffchainAsyncOrderPythLazerModule {
    function settleOffchainAsyncOrderPythLazer(
        OffchainOrder.Data memory order,
        OffchainOrder.Signature memory signature
    ) external;
}
