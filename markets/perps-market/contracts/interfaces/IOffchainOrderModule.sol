//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {OffchainOrder} from "../storage/OffchainOrder.sol";

interface IOffchainOrderModule {
    function settleOffchainOrder(
        OffchainOrder.Data memory firstOrder,
        OffchainOrder.Signature memory firstSignature,
        OffchainOrder.Data memory secondOrder,
        OffchainOrder.Signature memory secondSignature
    ) external;

    error UnauthorizedRelayer(address relayer);
}
