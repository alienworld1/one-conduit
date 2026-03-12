// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {HelloPVM} from "../src/HelloPVM.sol";

// Usage:
//   forge script script/DeployHelloPVM.s.sol --broadcast \
//     --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY \
//     --resolc
//
// Records deployed address — paste result into contracts/DEPLOYED_ADDRESSES.md
contract DeployHelloPVM is Script {
    function run() external returns (address) {
        vm.startBroadcast();
        HelloPVM hello = new HelloPVM();
        vm.stopBroadcast();
        return address(hello);
    }
}
