// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockCheckerClaimAndWithdraw {
    using SafeERC20 for IERC20;

    struct ClaimInfo {
        address wallet;
        uint48 cliffTimestamp;
        bool withdrawFinished;
        uint256 amount;
    }

    mapping(uint256 /* orderId */ => ClaimInfo) claimRecords;

    address public immutable aethirTokenAdress;

    /* cliffSeconds should greater than minCliffSeconds */
    uint48 private immutable minCliffSeconds;
    uint48 private immutable maxCliffSeconds;

    event EventAlreadyWithdraw(uint256 orderId);
    event EventWithdraw(uint256[] orderIdArray, uint256 withdrawAmount);
    event EventClaim(uint256 orderId, address wallet, uint48 cliffTimestamp, uint256 amount);

    constructor(address aethirTokenAdress_) {
        aethirTokenAdress = aethirTokenAdress_;
        maxCliffSeconds = 365 * 86400;
    }

    function getClaimInfo(uint256 orderId)
        external
        view
        returns (address wallet, uint48 cliffTimestamp, bool withdrawFinished, uint256 amount)
    {
        ClaimInfo storage claimInfo = claimRecords[orderId];
        wallet = claimInfo.wallet;
        cliffTimestamp = claimInfo.cliffTimestamp;
        withdrawFinished = claimInfo.withdrawFinished;
        amount = claimInfo.amount;
    }

    function claim(
        uint256 orderId,
        uint48 cliffSeconds,
        uint48 expiryTimestamp,
        uint256 amount,
        bytes[] memory
    ) external {
        require(cliffSeconds >= minCliffSeconds && cliffSeconds <= maxCliffSeconds, "invalid cliffSeconds");
        require(block.timestamp < expiryTimestamp, "order expired");
        require(amount > 0, "invalid amount");

        require(claimRecords[orderId].amount == 0, "orderId aready exists");

        ClaimInfo storage claimInfo = claimRecords[orderId];
        claimInfo.wallet = msg.sender;
        claimInfo.cliffTimestamp = uint48(block.timestamp + cliffSeconds);
        claimInfo.amount = amount;

        emit EventClaim(orderId, claimInfo.wallet, claimInfo.cliffTimestamp, claimInfo.amount);
    }

    function withdraw(uint256[] memory orderIdArray, uint48 expiryTimestamp, bytes[] memory) external {
        require(block.timestamp < expiryTimestamp, "order expired");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < orderIdArray.length; i++) {
            uint256 orderId = orderIdArray[i];
            ClaimInfo storage claimInfo = claimRecords[orderId];
            require(claimInfo.wallet == msg.sender, "invalid msg.sender");
            require(claimInfo.cliffTimestamp <= block.timestamp, "can not withdraw now");
            if (claimInfo.withdrawFinished == false) {
                totalAmount += claimInfo.amount;
                claimInfo.withdrawFinished = true;
            } else {
                emit EventAlreadyWithdraw(orderId);
            }
        }

        if (totalAmount > 0) {
            SafeERC20.safeTransfer(IERC20(aethirTokenAdress), msg.sender, totalAmount);
            emit EventWithdraw(orderIdArray, totalAmount);
        }
    }
}
