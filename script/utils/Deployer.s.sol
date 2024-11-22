// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2 as console} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {BaseScript} from "./Base.s.sol";

contract Deployer is BaseScript {
    /*--------------------------------------------------------------------------*/
    /* Errors                                                                   */
    /*--------------------------------------------------------------------------*/

    error AlreadyDeployed();

    /*--------------------------------------------------------------------------*/
    /* Structures                                                               */
    /*--------------------------------------------------------------------------*/

    struct Deployment {
        address yieldPass;
        address yieldPassUtils;
        address aethirYieldAdapter;
        address xaiYieldAdapter;
    }

    /*--------------------------------------------------------------------------*/
    /* State Variables                                                          */
    /*--------------------------------------------------------------------------*/

    Deployment internal _deployment;

    /*--------------------------------------------------------------------------*/
    /* Modifier                                                                 */
    /*--------------------------------------------------------------------------*/

    /**
     * @dev Add useDeployment modifier to deployment script run() function to
     *      deserialize deployments json and make properties available to read,
     *      write and modify. Changes are re-serialized at end of script.
     */
    modifier useDeployment() {
        console.log("Using deployment\n");
        console.log("Network: %s\n", _chainIdToNetwork[block.chainid]);

        _deserialize();

        _;

        _serialize();

        console.log("Using deployment completed\n");
    }

    /*--------------------------------------------------------------------------*/
    /* Internal Helpers                                                         */
    /*--------------------------------------------------------------------------*/

    /**
     * @notice Internal helper to get deployment file path for current network
     *
     * @return Path
     */
    function _getJsonFilePath() internal view returns (string memory) {
        return string(abi.encodePacked(vm.projectRoot(), "/deployments/", _chainIdToNetwork[block.chainid], ".json"));
    }

    /**
     * @notice Internal helper to read and return json string
     *
     * @return Json string
     */
    function _getJson() internal view returns (string memory) {
        string memory path = _getJsonFilePath();

        string memory json = "{}";

        try vm.readFile(path) returns (string memory _json) {
            json = _json;
        } catch {
            console.log("No json file found at: %s\n", path);
        }

        return json;
    }

    /*--------------------------------------------------------------------------*/
    /* API                                                                      */
    /*--------------------------------------------------------------------------*/

    /**
     * @notice Serialize the _deployment storage struct
     */
    function _serialize() internal {
        /* Initialize json string */
        string memory json = "";

        json = stdJson.serialize("", "YieldPass", _deployment.yieldPass);
        json = stdJson.serialize("", "YieldPassUtils", _deployment.yieldPassUtils);

        /* Adapters */
        json = stdJson.serialize("", "AethirYieldAdapter", _deployment.aethirYieldAdapter);
        json = stdJson.serialize("", "XaiYieldAdapter", _deployment.xaiYieldAdapter);

        console.log("Writing json to file: %s\n", json);
        vm.writeJson(json, _getJsonFilePath());
    }

    /**
     * @notice Deserialize the deployment json
     *
     * @dev Deserialization loads the json into the _deployment struct
     */
    function _deserialize() internal {
        string memory json = _getJson();

        /* Deserialize Yield Pass */
        try vm.parseJsonAddress(json, ".YieldPass") returns (address instance) {
            _deployment.yieldPass = instance;
        } catch {
            console.log("Could not parse YieldPass");
        }

        /* Deserialize Yield Pass Utils */
        try vm.parseJsonAddress(json, ".YieldPassUtils") returns (address instance) {
            _deployment.yieldPassUtils = instance;
        } catch {
            console.log("Could not parse YieldPassUtils");
        }

        /* Deserialize Aethir Yield Adapter */
        try vm.parseJsonAddress(json, ".AethirYieldAdapter") returns (address instance) {
            _deployment.aethirYieldAdapter = instance;
        } catch {
            console.log("Could not parse AethirYieldAdapter");
        }

        /* Deserialize XAI Yield Adapter */
        try vm.parseJsonAddress(json, ".XaiYieldAdapter") returns (address instance) {
            _deployment.xaiYieldAdapter = instance;
        } catch {
            console.log("Could not parse XaiYieldAdapter");
        }
    }
}
