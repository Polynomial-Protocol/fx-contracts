// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

library Price {
    struct Data {
        mapping(uint64 => int256) benchmarkPrices;
    }

    function load(bytes32 feedId) internal pure returns (Data storage price) {
        bytes32 s = keccak256(abi.encode("io.polynomial.fx-oracle-erc7412-wrapper.price", feedId));
        assembly {
            price.slot := s
        }
    }
}
