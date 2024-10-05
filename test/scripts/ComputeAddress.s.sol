// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

library ComputeAddress {
    function addressFrom(address _origin, uint256 _nonce) internal pure returns (address) {
        if (_nonce == 0x00) {
            return address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80)))))
            );
        }
        if (_nonce <= 0x7f) {
            return address(
                uint160(
                    uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(uint8(_nonce)))))
                )
            );
        }
        if (_nonce <= 0xff) {
            return address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce)))
                    )
                )
            );
        }
        if (_nonce <= 0xffff) {
            return address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce)))
                    )
                )
            );
        }
        if (_nonce <= 0xffffff) {
            return address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce)))
                    )
                )
            );
        }
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce))))
            )
        ); // more than 2^32 nonces not
            // realistic
    }
}
