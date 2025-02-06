// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";

import {BaseTest} from "../../Base.t.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";
import {TestNodeLicense} from "src/yieldAdapters/test/TestNodeLicense.sol";
import {TestYieldToken} from "src/yieldAdapters/test/TestYieldToken.sol";
import {TestYieldAdapter} from "src/yieldAdapters/test/TestYieldAdapter.sol";

/**
 * @title Test Yield Adapter base test setup
 * @author MetaStreet Foundation
 *
 * @dev Sets up contracts
 */
abstract contract TestYieldAdapterBaseTest is BaseTest {
    TestNodeLicense internal testNodeLicense;
    TestYieldToken internal testYieldToken;
    TestYieldAdapter internal yieldAdapter;
    uint64 internal startTime;
    uint64 internal expiryTime;

    address internal yp;
    address internal np;

    function setUp() public virtual override {
        BaseTest.setUp();

        startTime = uint64(block.timestamp);
        expiryTime = startTime + 15 days;

        vm.startPrank(users.deployer);

        /* Deploy Node License */
        testNodeLicense = new TestNodeLicense("Test Node License", "TEST-NODE");
        testNodeLicense.mint(users.normalUser1, 2);
        testNodeLicense.mint(users.normalUser2, 3);

        /* Deploy Yield Token */
        testYieldToken = new TestYieldToken("Test Yield Token", "TEST");

        /* Deploy Yield Adapter */
        TestYieldAdapter yieldAdapterImpl =
            new TestYieldAdapter(address(yieldPass), expiryTime, address(testNodeLicense), address(testYieldToken));
        yieldAdapter = TestYieldAdapter(
            address(new ERC1967Proxy(address(yieldAdapterImpl), abi.encodeWithSignature("initialize()")))
        );
        vm.label({account: address(yieldAdapter), newLabel: "Test Yield Adapter"});

        /* Grant mint role to yield adapter */
        testYieldToken.grantRole(testYieldToken.MINT_ROLE(), address(yieldAdapter));

        /* Deploy Yield Pass */
        (yp, np) = yieldPass.deployYieldPass(address(testNodeLicense), startTime, expiryTime, address(yieldAdapter));

        vm.stopPrank();

        /* Approve node licenses with yield adapter */
        vm.startPrank(users.normalUser1);
        testNodeLicense.setApprovalForAll(address(yieldAdapter), true);
        vm.stopPrank();
        vm.startPrank(users.normalUser2);
        testNodeLicense.setApprovalForAll(address(yieldAdapter), true);
        vm.stopPrank();
    }
}
