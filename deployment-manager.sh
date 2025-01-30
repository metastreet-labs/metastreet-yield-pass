#!/usr/bin/env bash

set -e

# deploy a contract
run() {
    local network="$1"
    local rpc_url_var="$2"
    local contract="$3"

    case $network in
        "local")
            echo "Running locally"
            forge script "$contract" --fork-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast -vvvv "${@:4}"
            ;;

        "goerli"|"sepolia"|"mainnet"|"blast"|"base"|"arbitrum_sepolia"|"arbitrum")
            local rpc_url="${!rpc_url_var}"
            if [[ -z $rpc_url ]]; then
                echo "$rpc_url_var is not set"
                exit 1
            fi
            echo "Running on $network"
            if [ ! -z $LEDGER_DERIVATION_PATH ]; then
                forge script "$contract" --rpc-url "$rpc_url" --ledger --hd-paths $LEDGER_DERIVATION_PATH --sender $LEDGER_ADDRESS --broadcast -vvvv "${@:4}"
            else
                forge script "$contract" --rpc-url "$rpc_url" --private-key $PRIVATE_KEY --broadcast -vvvv "${@:4}"
            fi
            ;;

        *)
            echo "Invalid NETWORK value"
            exit 1
            ;;
    esac
}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy-yield-pass"
    echo "  upgrade-yield-pass"
    echo "  deploy-yield-pass-utils <uniswap v2 factory>"
    echo "  upgrade-yield-pass-utils <uniswap v2 factory>"
    echo ""
    echo "  yield-pass-create <nft> <start time> <expiry time> <yield adapter>"
    echo ""
    echo "  deploy-aethir-yield-adapter <checker node license> <checker claim and withdraw> <cliff seconds> <signer> <is transfer unlocked>"
    echo "  upgrade-aethir-yield-adapter <proxy> <checker node license> <checker claim and withdraw>"
    echo ""
    echo "  deploy-xai-yield-adapter <xai pool factory> <is transfer unlocked>"
    echo "  upgrade-xai-yield-adapter <proxy> <xai pool factory>"
    echo "  add-pools-to-xai-yield-adapter <xai yield adapter> <pools>"
    echo "  remove-pools-from-xai-yield-adapter <xai yield adapter> <pools>"
    echo ""
    echo "  show"
    echo ""
    echo "Options:"
    echo "  NETWORK: Set this environment variable to either 'local' or a network name."
}

### deployment manager ###

DEPLOYMENTS_FILE="deployments/${NETWORK}.json"

if [[ -z "$NETWORK" ]]; then
    echo "Error: Set NETWORK."
    echo ""
    usage
    exit 1
fi

case $1 in
    "deploy-yield-pass")
        if [ "$#" -ne 1 ]; then
            echo "Invalid param count; Usage: $0 deploy-yield-pass"
            exit 1
        fi

        echo "Deploying Yield Pass"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployYieldPass.s.sol:DeployYieldPass" --sig "run()"
        ;;

    "upgrade-yield-pass")
        if [ "$#" -ne 1 ]; then
            echo "Invalid param count; Usage: $0 upgrade-yield-pass"
            exit 1
        fi

        echo "Upgrading Yield Pass"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/UpgradeYieldPass.s.sol:UpgradeYieldPass" --sig "run()"
        ;;

    "deploy-yield-pass-utils")
        if [ "$#" -ne 2 ]; then
            echo "Invalid param count; Usage: $0 deploy-yield-pass-utils <uniswap v2 factory>"
            exit 1
        fi

        echo "Deploying Yield Pass Utils"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/DeployYieldPassUtils.s.sol:DeployYieldPassUtils" --sig "run(address)" $2
        ;;

    "upgrade-yield-pass-utils")
        if [ "$#" -ne 2 ]; then
            echo "Invalid param count; Usage: $0 upgrade-yield-pass-utils <uniswap v2 factory>"
            exit 1
        fi

        echo "Upgrading Yield Pass Utils"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/UpgradeYieldPassUtils.s.sol:UpgradeYieldPassUtils" --sig "run(address)" $2
        ;;

    "yield-pass-create")
        if [ "$#" -ne 5 ]; then
            echo "Invalid param count; Usage: $0 yield-pass-create <nft> <start time> <expiry time> <yield adapter>"
            exit 1
        fi

        echo "Creating Yield Pass Token"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/YieldPassCreate.s.sol:YieldPassCreate" --sig "run(address,uint64,uint64,address)" $2 $3 $4 $5
        ;;

    "deploy-aethir-yield-adapter")
        if [ "$#" -ne 6 ]; then
            echo "Invalid param count; Usage: $0 deploy-aethir-yield-adapter <checker node license> <checker claim and withdraw> <cliff seconds> <signer> <is transfer unlocked>"
            exit 1
        fi

        echo "Deploying Aethir Yield Adapter"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/yieldAdapters/aethir/DeployAethirYieldAdapter.s.sol:DeployAethirYieldAdapter" --sig "run(address,address,uint48,address,bool)" $2 $3 $4 $5 $6
        ;;

    "upgrade-aethir-yield-adapter")
        if [ "$#" -ne 4 ]; then
            echo "Invalid param count; Usage: $0 upgrade-aethir-yield-adapter <proxy> <checker node license> <checker claim and withdraw>"
            exit 1
        fi

        echo "Upgrading Aethir Yield Adapter"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/yieldAdapters/aethir/UpgradeAethirYieldAdapter.s.sol:UpgradeAethirYieldAdapter" --sig "run(address,address,address)" $2 $3 $4
        ;;

    "deploy-xai-yield-adapter")
        if [ "$#" -ne 3 ]; then
            echo "Invalid param count; Usage: $0 deploy-xai-yield-adapter <xai pool factory> <is transfer unlocked>"
            exit 1
        fi

        echo "Deploying XAI Yield Adapter"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/yieldAdapters/xai/DeployXaiYieldAdapter.s.sol:DeployXaiYieldAdapter" --sig "run(address,bool)" $2 $3
        ;;

    "upgrade-xai-yield-adapter")
        if [ "$#" -ne 3 ]; then
            echo "Invalid param count; Usage: $0 upgrade-xai-yield-adapter <proxy> <xai pool factory>"
            exit 1
        fi

        echo "Upgrading XAI Yield Adapter"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/yieldAdapters/xai/UpgradeXaiYieldAdapter.s.sol:UpgradeXaiYieldAdapter" --sig "run(address,address)" $2 $3
        ;;

    "add-pools-to-xai-yield-adapter")
        if [ "$#" -ne 3 ]; then
            echo "Invalid param count; Usage: $0 add-pools-to-xai-yield-adapter <xai yield adapter> <pools>"
            exit 1
        fi

        echo "Adding pools to XAI Yield Adapter"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/yieldAdapters/xai/AddPoolsToXaiYieldAdapter.s.sol:AddPoolsToXaiYieldAdapter" --sig "run(address,address[])" $2 $3
        ;;

    "remove-pools-from-xai-yield-adapter")
        if [ "$#" -ne 3 ]; then
            echo "Invalid param count; Usage: $0 remove-pools-from-xai-yield-adapter <xai yield adapter> <pools>"
            exit 1
        fi

        echo "Removing pools from XAI Yield Adapter"
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/yieldAdapters/xai/RemovePoolsFromXaiYieldAdapter.s.sol:RemovePoolsFromXaiYieldAdapter" --sig "run(address,address[])" $2 $3
        ;;

    "show")
        run "$NETWORK" "${NETWORK^^}_RPC_URL" "script/Show.s.sol:Show" --sig "run()"
        ;;
    *)
        usage
        exit 1
        ;;
esac
