// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockMetaStreetPool {
    IERC20 private _token;

    constructor(
        address token
    ) {
        _token = IERC20(token);
    }

    function borrow(
        uint256 principal,
        uint64,
        address collateralToken,
        uint256 collateralTokenId,
        uint256,
        uint128[] calldata,
        bytes calldata
    ) external returns (uint256) {
        IERC721(collateralToken).transferFrom(msg.sender, address(this), collateralTokenId);
        _token.approve(address(this), principal);
        _token.transferFrom(address(this), msg.sender, principal);

        return principal;
    }
}
