// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {BaseTest} from "../Base.t.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IPoolFactory} from "metastreet-contracts-v2/interfaces/IPoolFactory.sol";
import {IPool} from "metastreet-contracts-v2/interfaces/IPool.sol";

import {Helpers} from "./Helpers.sol";

contract PoolBaseTest is BaseTest {
    uint64[] internal durations = [30 days, 14 days, 7 days];
    uint64[] internal rates =
        [Helpers.normalizeRate(0 * 1e18), Helpers.normalizeRate(0.3 * 1e18), Helpers.normalizeRate(0.5 * 1e18)];

    IPoolFactory internal metaStreetPoolFactory;
    address internal metaStreetPoolImpl;
    IPool internal metaStreetPool;
    address internal bundleCollateralWrapper;

    function setUp() public virtual override {
        /* Set up Base */
        BaseTest.setUp();
    }

    /*--------------------------------------------------------------------------*/
    /* Setup Helpers                                                            */
    /*--------------------------------------------------------------------------*/

    function setMetaStreetPoolFactoryAndImpl(address poolFactory_, address poolImpl_) internal {
        metaStreetPoolFactory = IPoolFactory(poolFactory_);

        metaStreetPoolImpl = poolImpl_;
    }

    /* Deploy WeightedRateCollection pool */
    function deployMetaStreetPool(address nft, address tok, address priceOracle) internal {
        vm.prank(users.deployer);

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = nft;

        /* Set pool parameters */
        bytes memory poolParams = abi.encode(collateralTokens, tok, priceOracle, durations, rates);

        /* Deploy pool proxy */
        metaStreetPool = IPool(metaStreetPoolFactory.createProxied(address(metaStreetPoolImpl), poolParams));
        vm.label({account: address(metaStreetPool), newLabel: "Pool"});
    }

    function setERC20Approvals() internal {}

    function setERC721Approvals() internal {}
}
