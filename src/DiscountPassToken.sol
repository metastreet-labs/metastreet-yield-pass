// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title Discount Token (ERC721)
 * @author MetaStreet Foundation
 */
contract DiscountPassToken is ERC721 {
    /*------------------------------------------------------------------------*/
    /* Error */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Not transferable
     */
    error NotTransferable();

    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Owner
     */
    address internal immutable _owner;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice True if token is transferable
     */
    bool internal _isTransferable;

    /*------------------------------------------------------------------------*/
    /* Contructor */
    /*------------------------------------------------------------------------*/

    constructor(string memory name_, string memory symbol_, bool isTransferable_) ERC721(name_, symbol_) {
        _owner = msg.sender;

        _isTransferable = isTransferable_;
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get if token is transferable
     * @return True if token is transferable
     */
    function isTransferable() external view returns (bool) {
        return _isTransferable;
    }

    /*------------------------------------------------------------------------*/
    /* Discount Token API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint discount token
     * @param to Account
     * @param tokenId Token ID
     */
    function mint(address to, uint256 tokenId) external {
        require(msg.sender == _owner, "Unauthorized caller");

        _mint(to, tokenId);
    }

    /**
     * @notice Burn discount token
     * @param tokenId Token ID
     */
    function burn(uint256 tokenId) external {
        require(msg.sender == _owner, "Unauthorized caller");

        _burn(tokenId);
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Set if token is transferable
     * @param isTransferable_ True if token is transferable
     */
    function setTransferable(bool isTransferable_) external {
        require(msg.sender == _owner, "Unauthorized caller");

        _isTransferable = isTransferable_;
    }

    /*------------------------------------------------------------------------*/
    /* Overrides */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC721
     * @dev Only added transferrability validation, remaining logic is same as in ERC721
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        /* Allow only if transferability is set to true or token is being burned or minted */
        if (!_isTransferable && to != address(0) && from != address(0)) revert NotTransferable();

        return super._update(to, tokenId, auth);
    }
}
