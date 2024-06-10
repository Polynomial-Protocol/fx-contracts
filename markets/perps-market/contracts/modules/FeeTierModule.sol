    //SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "../storage/FeeTier.sol";
import "../interfaces/IFeeTierModule.sol";

contract FeeTierModule is IFeeTierModule {
    /**
     * @inheritdoc IFeeTierModule
     */
    function setFeeTier(uint256 id, uint256 makerDiscountInBps, uint256 takerDiscountInBps, bytes memory signature) external override {
        // FIXME: validate signature
        
        FeeTier.Data storage config = FeeTier.load(id);
        config.makerDiscountInBps = makerDiscountInBps;
        config.takerDiscountInBps = takerDiscountInBps;

        emit FeeTierSet(id, makerDiscountInBps, takerDiscountInBps);
    }

    /**
     * @inheritdoc IFeeTierModule
     */
    function getFeeTier(uint256 id) external view override returns (uint256, uint256) {
        FeeTier.Data storage config = FeeTier.load(id);
        return (config.makerDiscountInBps, config.takerDiscountInBps);
    }
}
