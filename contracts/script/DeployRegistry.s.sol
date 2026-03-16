// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ConduitRegistry} from "../src/ConduitRegistry.sol";

/// @notice Deploys ConduitRegistry to the target network.
///
/// Usage:
///   forge script contracts/script/DeployRegistry.s.sol \
///     --rpc-url $ETH_RPC_URL \
///     --private-key $PRIVATE_KEY \
///     --broadcast
///
/// After deployment, record the address in contracts/DEPLOYED_ADDRESSES.md.
///
/// Note: This script deploys the registry only — it does NOT register any adapters.
/// Adapter registration happens in Module 3's deploy script after adapters are deployed.
contract DeployRegistry is Script {
    function run() external {
        vm.startBroadcast();

        ConduitRegistry registry = new ConduitRegistry();

        vm.stopBroadcast();

        console2.log("ConduitRegistry deployed at:", address(registry));
        console2.log("Owner:", registry.owner());
        console2.log("Product count (should be 0):", registry.getProductCount());
    }
}
