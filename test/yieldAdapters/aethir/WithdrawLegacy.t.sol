// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {AethirBaseTest} from "./Base.t.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {IYieldAdapter} from "src/interfaces/IYieldAdapter.sol";
import {YieldPass} from "src/YieldPass.sol";

import {AethirYieldAdapter, IERC4907} from "src/yieldAdapters/aethir/AethirYieldAdapter.sol";

import "forge-std/console.sol";

contract WtihdrawLegacyTest is AethirBaseTest {
    function test__WithdrawLegacy() external {
        vm.rollFork(317179100);

        /* Yield pass factory in prod */
        address proxy = 0x24147F47B916bcF7E0a8810f859bA3bf703d436d;

        /* Aethir yield pass in prod */
        address yp = 0x70c5aD55c1A3f94D62cF9c81ad065377175Beca2;

        /* User */
        address user = 0xBE878c39929ED3e79A9fFf31a4415dA9A45Fa73c;

        /* Token id */
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 64682;

        /* Approved user */
        vm.startPrank(0x7fF005945Fef2BE9918d31F0a8B279647cA8A997);

        /* Deploy new yield pass */
        YieldPass yieldPassFactory = new YieldPass();

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ERC1967Utils.ADMIN_SLOT))));

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), address(yieldPassFactory), "");

        vm.stopPrank();

        vm.startPrank(user);
        YieldPass(proxy).redeem(yp, user, tokenIds);
        YieldPass(proxy).withdraw(yp, tokenIds);
        vm.stopPrank();

        assertEq(IERC721(checkerNodeLicense).ownerOf(tokenIds[0]), user);
    }
}
