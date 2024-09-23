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
        [Helpers.normalizeRate(0.1 * 1e18), Helpers.normalizeRate(0.3 * 1e18), Helpers.normalizeRate(0.5 * 1e18)];

    IPoolFactory internal poolFactory;
    address internal poolImpl;
    IPool internal pool;

    function setUp() public virtual override {
        /* Set up Base */
        BaseTest.setUp();
    }

    /*--------------------------------------------------------------------------*/
    /* Setup Helpers                                                            */
    /*--------------------------------------------------------------------------*/

    function setPoolFactoryAndPoolImpl(address poolFactory_, address poolImpl_) internal {
        poolFactory = IPoolFactory(poolFactory_);

        poolImpl = poolImpl_;
    }

    function deployPool(address nft, address tok, address priceOracle) internal {
        vm.prank(users.deployer);

        /* Set pool parameters */
        bytes memory poolParams = abi.encode(nft, tok, priceOracle, durations, rates);

        /* Deploy pool proxy */
        pool = IPool(poolFactory.create(address(poolImpl), poolParams));
        vm.label({account: address(pool), newLabel: "Pool"});
    }

    function setERC20Approvals() internal {}

    function setERC721Approvals() internal {}
}
