// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title Discount Pass Token (ERC721)
 * @author MetaStreet Foundation
 */
contract DiscountPassToken is ERC721 {
    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Emitted when user locked is set
     * @param isUserLocked True if user locked enabled
     */
    event UserLockedSet(bool isUserLocked);

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
     * @notice True if user locked enabled
     */
    bool internal _isUserLocked;

    /**
     * @notice Token ID to account mapping
     */
    mapping(uint256 => address) internal _tokenIdLocks;

    /*------------------------------------------------------------------------*/
    /* Contructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice DiscountPassToken constructor
     */
    constructor(string memory name_, string memory symbol_, bool isUserLocked_) ERC721(name_, symbol_) {
        _owner = msg.sender;

        _isUserLocked = isUserLocked_;
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get if token is user locked
     * @return True if token is user locked
     */
    function isUserLocked() external view returns (bool) {
        return _isUserLocked;
    }

    /**
     * @notice Get token ID to account lock
     * @param tokenId Token ID
     * @return Locked account address
     */
    function tokenIdLocks(
        uint256 tokenId
    ) external view returns (address) {
        return _isUserLocked ? _tokenIdLocks[tokenId] : address(0);
    }

    /*------------------------------------------------------------------------*/
    /* Discount Token API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Mint discount tokens
     * @param to Account
     * @param tokenIds Token IDs
     */
    function mint(address to, uint256[] calldata tokenIds) external {
        require(msg.sender == _owner, "Unauthorized caller");

        for (uint256 i; i < tokenIds.length; i++) {
            _tokenIdLocks[tokenIds[i]] = to;

            _mint(to, tokenIds[i]);
        }
    }

    /**
     * @notice Burn discount token
     * @param from Account
     * @param tokenId Token ID
     */
    function burn(address from, uint256 tokenId) external {
        require(msg.sender == _owner, "Unauthorized caller");
        require(!_isUserLocked || _tokenIdLocks[tokenId] == from, "Invalid burn");

        delete _tokenIdLocks[tokenId];

        _burn(tokenId);
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Set user locked
     * @param isUserLocked_ True if user locked enabled
     */
    function setUserLocked(
        bool isUserLocked_
    ) external {
        require(msg.sender == _owner, "Unauthorized caller");

        _isUserLocked = isUserLocked_;

        emit UserLockedSet(isUserLocked_);
    }
}
