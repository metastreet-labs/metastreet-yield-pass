// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

interface IERC4907 {
    event UpdateUser(uint256 indexed tokenId, address indexed user, uint64 expires);

    function setUser(uint256 tokenId, address user, uint64 expires) external;
    function userOf(
        uint256 tokenId
    ) external view returns (address);
    function userExpires(
        uint256 tokenId
    ) external view returns (uint256);
}

contract CheckerLicenseNFT is Ownable2StepUpgradeable, ERC721EnumerableUpgradeable, IERC4907 {
    struct UserInfo {
        address user; // address of user role
        uint64 expires; // unix timestamp, user expires
    }

    event EventWhiteListAdminUpdated(address newWhiteListAdmin);
    event EventMinterAdminUpdated(address newMinterAdmin);
    event EventBanAdminUpdated(address newBanAdmin);
    event EventNftTransferableUpdated(bool transferable);
    event EventBanUpdated(address tokenOwner, uint256 tokenId, uint64 banEndTime);

    mapping(uint256 => UserInfo) internal _users;
    mapping(uint256 /* tokenId */ => uint64 /* ban end timestamp */) internal _banRecords;
    mapping(address => bool) internal _transferFromWhitelist;
    uint256 private _whitelistTransferStartTime;
    uint256 private _whitelistTransferEndTime;
    bool public nftTransferable;

    string public baseUrl;

    address public minterAdminAddress;
    address public banAdminAddress;
    address public whitelistAdminAddress;
    uint256 public nextTokenId;

    mapping(address => bool) internal _transferToWhitelist;

    constructor() {}

    // NFT claim contracts can call this function to mint NFTs
    function mint(address to, uint256 amount) public {
        require(msg.sender == minterAdminAddress || msg.sender == owner(), "caller is not the minter");
        for (uint256 i = 0; i < amount; i++) {
            _mintOne(to);
        }
    }

    function _mintOne(
        address to
    ) internal {
        _mint(to, nextTokenId);
        nextTokenId++;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseUrl;
    }

    function setBaseUrl(
        string calldata url_
    ) public onlyOwner {
        baseUrl = url_;
    }

    /// @notice set the user and expires of a NFT
    /// @dev The zero address indicates there is no user
    /// Throws if `tokenId` is not valid NFT
    /// @param user  The new user of the NFT
    /// @param expires  UNIX timestamp, The new user could use the NFT before expires
    function setUser(uint256 tokenId, address user, uint64 expires) public virtual {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC4907: caller is not owner nor approved");
        require(isBanned(tokenId) == false, "token is banned");
        _setUser(tokenId, user, expires);
    }

    function _setUser(uint256 tokenId, address user, uint64 expires) internal {
        UserInfo storage info = _users[tokenId];
        info.user = user;
        info.expires = expires;
        emit UpdateUser(tokenId, user, expires);
    }

    function batchSetUser(uint256[] calldata tokenIds, address[] calldata users, uint64 expires) public {
        require(tokenIds.length == users.length, "array length should be same");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            setUser(tokenIds[i], users[i], expires);
        }
    }

    /// @notice Get the user address of an NFT
    /// @dev The zero address indicates that there is no user or the user is expired
    /// @param tokenId The NFT to get the user address for
    /// @return The user address for this NFT
    function userOf(
        uint256 tokenId
    ) public view virtual returns (address) {
        if (uint256(_users[tokenId].expires) >= block.timestamp) {
            return _users[tokenId].user;
        } else {
            return address(0);
        }
    }

    /// @notice Get the user expires of an NFT
    /// @dev The zero value indicates that there is no user
    /// @param tokenId The NFT to get the user expires for
    /// @return The user expires for this NFT
    function userExpires(
        uint256 tokenId
    ) public view virtual returns (uint256) {
        return _users[tokenId].expires;
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return interfaceId == type(IERC4907).interfaceId || super.supportsInterface(interfaceId);
    }

    function getBanEndTime(
        uint256 tokenId
    ) public view returns (uint64) {
        return _banRecords[tokenId];
    }

    function isBanned(
        uint256 tokenId
    ) public view returns (bool) {
        return _banRecords[tokenId] > block.timestamp;
    }

    function ban(uint256 tokenId, uint64 endTime) public {
        require(msg.sender == banAdminAddress, "only ban admin");
        require(endTime > block.timestamp, "invalid end time");
        require(_exists(tokenId), "invalid token id");
        _banRecords[tokenId] = endTime;
        emit EventBanUpdated(ownerOf(tokenId), tokenId, endTime);
    }

    function unBan(
        uint256 tokenId
    ) public {
        require(msg.sender == banAdminAddress, "only ban admin");
        _banRecords[tokenId] = 0;
        emit EventBanUpdated(ownerOf(tokenId), tokenId, 0);
    }

    /**
     * @dev See {ERC721-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        require(isBanned(firstTokenId) == false, "token is banned");
        if (from != address(0) && !nftTransferable) {
            _checkWhitelistTransfer(from, to);
        }

        if (from != to && _users[firstTokenId].user != address(0)) {
            _setUser(firstTokenId, address(0), 0);
        }
    }

    function _checkWhitelistTransfer(address fromAddress, address toAddress) internal view {
        require(
            (msg.sender == fromAddress && _transferFromWhitelist[fromAddress]) || _transferToWhitelist[toAddress],
            "not in transfer whitelist"
        );
        require(
            _whitelistTransferStartTime <= block.timestamp && block.timestamp <= _whitelistTransferEndTime,
            "not in whitelist transfer time range"
        );
    }

    function batchTransfer(address[] calldata toArray, uint256[] calldata tokenIdArray) public {
        require(toArray.length == tokenIdArray.length, "array length should be same");
        for (uint256 i = 0; i < toArray.length; i++) {
            transferFrom(msg.sender, toArray[i], tokenIdArray[i]);
        }
    }

    function tokenIdsOfOwnerByAmount(address user, uint256 amount) external view returns (uint256[] memory tokenIds) {
        uint256 total = balanceOf(user);
        require(amount > 0, "invalid count");
        require(amount <= total, "invalid count");

        tokenIds = new uint256[](amount);
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            tokenIds[i] = tokenId;
        }
    }

    function updateTransferWhiteList(
        address[] calldata addressFromList,
        bool inFromWhitelist,
        address[] calldata addressToList,
        bool inToWhitelist
    ) public {
        require(msg.sender == whitelistAdminAddress, "only whitelist admin");
        for (uint256 i = 0; i < addressFromList.length; i++) {
            _transferFromWhitelist[addressFromList[i]] = inFromWhitelist;
        }
        for (uint256 i = 0; i < addressToList.length; i++) {
            _transferToWhitelist[addressToList[i]] = inToWhitelist;
        }
    }

    function updateWhitelistTransferTime(uint256 startTime, uint256 endTime) public {
        require(msg.sender == whitelistAdminAddress, "only whitelist admin");
        _whitelistTransferStartTime = startTime;
        _whitelistTransferEndTime = endTime;
    }

    function getWhitelistTransferTime() public view returns (uint256 startTime, uint256 endTime) {
        startTime = _whitelistTransferStartTime;
        endTime = _whitelistTransferEndTime;
    }

    function updateNftTransferable(
        bool transferable
    ) public onlyOwner {
        nftTransferable = transferable;
        emit EventNftTransferableUpdated(transferable);
    }

    function inTransferWhitelist(
        address addr
    ) public view returns (bool) {
        return _transferFromWhitelist[addr] || _transferToWhitelist[addr];
    }

    function updateMinterAdmin(
        address minter
    ) public onlyOwner {
        minterAdminAddress = minter;
        emit EventMinterAdminUpdated(minterAdminAddress);
    }

    function updateWhitelistAdmin(
        address whitelistAdmin
    ) public onlyOwner {
        whitelistAdminAddress = whitelistAdmin;
        emit EventWhiteListAdminUpdated(whitelistAdminAddress);
    }

    function updateBanAdmin(
        address banAdmin
    ) public onlyOwner {
        banAdminAddress = banAdmin;
        emit EventBanAdminUpdated(banAdminAddress);
    }
}
