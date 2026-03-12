// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {HelloCaller} from "../src/HelloCaller.sol";

// Usage:
//   HELLO_INK_ADDRESS=0x... forge script script/DeployHelloCaller.s.sol \
//     --broadcast --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY \
//     --resolc
//
// Set HELLO_INK_ADDRESS to the address printed by `cargo contract instantiate`
// when you deployed HelloInk. See docs/SETUP.md — "Deploy HelloInk" section.
contract DeployHelloCaller is Script {
    function run() external returns (address) {
        address inkAddr = vm.envAddress("HELLO_INK_ADDRESS");
        vm.startBroadcast();
        HelloCaller caller = new HelloCaller(inkAddr);
        vm.stopBroadcast();
        return address(caller);
    }
}
