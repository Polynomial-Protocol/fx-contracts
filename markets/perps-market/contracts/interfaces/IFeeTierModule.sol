//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

interface IFeeTierModule {

    /**
    * @notice emits when discount for a fee tier changes
    * @param id id of the fee tier.
    * @param makerDiscountInBps maker discount in bps.
    * @param takerDiscountInBps taker discount in bps.
     */
     event FeeTierSet(uint256 id, uint256 makerDiscountInBps, uint256 takerDiscountInBps);

    /**
    * @notice sets discount for a fee tier
    * @param id id of the fee tier.
    * @param makerDiscountInBps maker discount in bps.
    * @param takerDiscountInBps taker discount in bps.
    */
    function setFeeTier(uint256 id, uint256 makerDiscountInBps, uint256 takerDiscountInBps) external;

    /**
    * @notice gets fee discount for a fee tier
    * @param  id of the market.
    * @return discount for a fee tier.  
    */
    function getFeeTier(uint256 id) external view returns (uint256, uint256);



}