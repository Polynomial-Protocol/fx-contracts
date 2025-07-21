//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

library Price {
    struct Data {
        uint64 price;
        uint64 timestamp;
        int16 exponent;
        mapping(uint64 => uint256) benchmarkPrices;
    }

    function load(uint32 feedId) internal pure returns (Data storage price) {
        bytes32 s = keccak256(abi.encode("fi.polynomial.pyth-lazer-erc7412-wrapper.price", feedId));
        assembly {
            price.slot := s
        }
    }

    function setPrice(Data storage self, uint64 price, uint64 timestamp, int16 exponent) internal {
        self.price = price;
        self.timestamp = timestamp;
        self.exponent = exponent;
    }
}
