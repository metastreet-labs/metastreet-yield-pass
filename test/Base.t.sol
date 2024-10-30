// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {TestERC721} from "./tokens/TestERC721.sol";
import {TestERC20} from "./tokens/TestERC20.sol";
import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldPassUtils} from "src/interfaces/IYieldPassUtils.sol";
import {YieldPass} from "src/YieldPass.sol";
import {YieldPassUtils, IBundleCollateralWrapper} from "src/YieldPassUtils.sol";

import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";

/**
 * @title Base test setup
 *
 * @author MetaStreet Foundation
 * @author Modified from https://github.com/PaulRBerg/prb-proxy/blob/main/test/Base.t.sol
 *
 * @dev Sets up users and token contracts
 */
abstract contract BaseTest is Test {
    /**
     * @notice User accounts
     */
    struct Users {
        address payable deployer;
        address payable normalUser1;
        address payable normalUser2;
        address payable admin;
        address payable liquidator;
        address payable borrower;
        address payable depositor;
    }

    Users internal users;
    TestERC20 internal tok;
    TestERC721 internal nft;
    TransparentUpgradeableProxy internal yieldPassProxy;
    IYieldPass internal yieldPassImpl;
    IYieldPass internal yieldPass;
    TransparentUpgradeableProxy internal yieldPassUtilsProxy;
    IYieldPassUtils internal yieldPassUtilsImpl;
    IYieldPassUtils internal yieldPassUtils;

    function setUp() public virtual {
        users = Users({
            deployer: createUser("deployer"),
            normalUser1: createUser("normalUser1"),
            normalUser2: createUser("normalUser2"),
            admin: createUser("admin"),
            liquidator: createUser("liquidator"),
            borrower: createUser("borrower"),
            depositor: createUser("depositor")
        });

        deployYieldPass();
    }

    function deployERC721() internal {
        vm.startPrank(users.deployer);

        /* Deploy NFT */
        nft = new TestERC721("NFT", "NFT", "https://nft1.com/token/");

        /* Mint NFT to users */
        nft.mint(address(users.normalUser1), 123);
        nft.mint(address(users.normalUser2), 124);

        vm.stopPrank();
    }

    function deployERC20() internal {
        vm.prank(users.deployer);

        /* Deploy ERC20 */
        tok = new TestERC20("TOK", "TOK", 18, 1000 ether);
    }

    function deployYieldPass() internal {
        vm.startPrank(users.deployer);

        /* Deploy yield pass implementation */
        yieldPassImpl = new YieldPass();

        /* Deploy yield pass proxy */
        yieldPassProxy = new TransparentUpgradeableProxy(
            address(yieldPassImpl), address(users.admin), abi.encodeWithSignature("initialize()")
        );

        /* Deploy yield pass */
        yieldPass = YieldPass(address(yieldPassProxy));
        vm.stopPrank();
    }

    function deployYieldPassUtils(address uniswapV2Router, address bundleCollateralWrapper_) internal {
        vm.startPrank(users.deployer);

        /* Deploy yield pass utils implementation */
        yieldPassUtilsImpl =
            new YieldPassUtils(IUniswapV2Router02(uniswapV2Router), yieldPass, bundleCollateralWrapper_);

        /* Deploy yield pass utils proxy */
        yieldPassUtilsProxy = new TransparentUpgradeableProxy(address(yieldPassUtilsImpl), address(users.admin), "");

        /* Deploy yield pass utils */
        yieldPassUtils = YieldPassUtils(address(yieldPassUtilsProxy));
        vm.stopPrank();
    }

    function createUser(string memory name) internal returns (address payable addr) {
        addr = payable(makeAddr(name));
        vm.label({account: addr, newLabel: name});
        vm.deal({account: addr, newBalance: 100 ether});
    }
}
