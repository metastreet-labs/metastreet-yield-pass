// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {XaiYieldAdapter} from "src/yieldAdapters/xai/XaiYieldAdapter.sol";
import {IYieldPass} from "src/interfaces/IYieldPass.sol";
import {Deployer} from "../../utils/Deployer.s.sol";

contract PatchHarvestAmount is Deployer {
    function run(address proxy, uint64 yieldPassExpiry, address xaiPoolFactory) public useDeployment {
        /* Deploy new XaiYieldAdapter Implementation */
        console.log("Deploying XaiYieldAdapter implementation...");

        XaiYieldAdapter yieldAdapterImpl = new XaiYieldAdapter(_deployment.yieldPass, yieldPassExpiry, xaiPoolFactory);

        console.log("XaiYieldAdapter implementation deployed at: %s\n", address(yieldAdapterImpl));

        console.log("Upgrading proxy %s implementation...", proxy);

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ERC1967Utils.ADMIN_SLOT))));

        /* Start prank */
        vm.startPrank(Ownable(proxyAdmin).owner());

        /* Upgrade Proxy */
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), address(yieldAdapterImpl), "");
        console.log("Upgraded proxy %s implementation to: %s\n", proxy, address(yieldAdapterImpl));

        /* Patch harvest amount */
        console.log("Patching harvest amount...");
        address xaiYieldPass = 0xCCcb5C4ee42f08D5baA724d3C74AA314a62aF3ba;
        address esXaiToken = 0x4C749d097832DE2FEcc989ce18fDc5f1BD76700c;
        bytes memory harvestData = abi.encode(xaiYieldPass);

        /* Compute before */
        uint256 totalBefore = IYieldPass(_deployment.yieldPass).claimState(xaiYieldPass).total;
        console.log("Total before harvest: %s", totalBefore);
        uint256 balanceBefore = IERC20(esXaiToken).balanceOf(proxy);
        console.log("Balance before harvest: %s", balanceBefore);

        /* Harvest */
        uint256 yieldAmount = IYieldPass(_deployment.yieldPass).harvest(xaiYieldPass, harvestData);
        console.log("Harvest yield amount: %s", yieldAmount);

        /* Compute after */
        uint256 totalAfter = IYieldPass(_deployment.yieldPass).claimState(xaiYieldPass).total;
        console.log("Total after harvest: %s", totalAfter);
        uint256 balanceAfter = IERC20(esXaiToken).balanceOf(proxy);
        console.log("Balance after harvest: %s", balanceAfter);

        /* Compute cumulative yield */
        uint256 cumulativeYield = IYieldPass(_deployment.yieldPass).cumulativeYield(xaiYieldPass);
        console.log("Cumulative yield: %s", cumulativeYield);

        /* Validate */
        console.log("Validate yield amount...");
        require(totalAfter == balanceAfter && totalAfter == cumulativeYield, "Yield amount mismatch");
        console.log("Yield amount validated");

        /* Stop prank */
        vm.stopPrank();
    }
}
