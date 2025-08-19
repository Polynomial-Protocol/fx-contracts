// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library PythLazerLib {
    enum PriceFeedProperty {
        Price,
        BestBidPrice,
        BestAskPrice,
        PublisherCount,
        Exponent
    }

    enum Channel {
        Invalid,
        RealTime,
        FixedRate50,
        FixedRate200
    }

    function parsePayloadHeader(
        bytes memory update
    ) internal pure returns (uint64 timestamp, Channel channel, uint8 feedsLen, uint16 pos) {
        uint32 FORMAT_MAGIC = 2479346549;

        pos = 0;
        uint32 magic;
        assembly {
            // Pointer = update + 32 (skip the length word) + pos
            let ptr := add(add(update, 0x20), pos)
            // mload(ptr) reads 32 bytes; shr(224, ...) keeps only the first 4 bytes
            magic := shr(224, mload(ptr))
        }
        pos += 4;
        if (magic != FORMAT_MAGIC) {
            revert("invalid magic");
        }
        // solhint-disable-next-line numcast/safe-cast
        uint64 temp;
        assembly {
            let ptr := add(add(update, 0x20), pos)
            temp := shr(192, mload(ptr))
        }
        timestamp = temp;
        pos += 8;
        // solhint-disable-next-line numcast/safe-cast
        channel = Channel(uint8(update[pos]));
        pos += 1;
        // solhint-disable-next-line numcast/safe-cast
        feedsLen = uint8(update[pos]);
        pos += 1;
    }

    function parseFeedHeader(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint32 feed_id, uint8 num_properties, uint16 new_pos) {
        // solhint-disable-next-line numcast/safe-cast
        assembly {
            let ptr := add(add(update, 0x20), pos)
            feed_id := shr(224, mload(ptr))
        }
        pos += 4;
        // solhint-disable-next-line numcast/safe-cast
        num_properties = uint8(update[pos]);
        pos += 1;
        new_pos = pos;
    }

    function parseFeedProperty(
        bytes memory update,
        uint16 pos
    ) internal pure returns (PriceFeedProperty property, uint16 new_pos) {
        // solhint-disable-next-line numcast/safe-cast
        property = PriceFeedProperty(uint8(update[pos]));
        pos += 1;
        new_pos = pos;
    }

    function parseFeedValueUint64(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint64 value, uint16 new_pos) {
        // solhint-disable-next-line numcast/safe-cast
        assembly {
            let ptr := add(add(update, 0x20), pos)
            value := shr(192, mload(ptr))
        }
        pos += 8;
        new_pos = pos;
    }

    function parseFeedValueUint16(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint16 value, uint16 new_pos) {
        // solhint-disable-next-line numcast/safe-cast
        assembly {
            let ptr := add(add(update, 0x20), pos)
            value := shr(240, mload(ptr))
        }
        pos += 2;
        new_pos = pos;
    }

    function parseFeedValueInt16(
        bytes memory update,
        uint16 pos
    ) internal pure returns (int16 value, uint16 new_pos) {
        // solhint-disable-next-line numcast/safe-cast
        assembly {
            let ptr := add(add(update, 0x20), pos)
            value := shr(240, mload(ptr))
        }
        pos += 2;
        new_pos = pos;
    }

    function parseFeedValueUint8(
        bytes memory update,
        uint16 pos
    ) internal pure returns (uint8 value, uint16 new_pos) {
        // solhint-disable-next-line numcast/safe-cast
        value = uint8(update[pos]);
        pos += 1;
        new_pos = pos;
    }
}
