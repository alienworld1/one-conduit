// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

contract ForceSend {
    constructor() payable {}

    function destroy(address payable to) external {
        selfdestruct(to);
    }
}

contract ForceFundAdapter is Script {
    function run() external {
        address payable adapter = payable(vm.envAddress("XCM_ADAPTER_ADDRESS"));
        uint256 amount = vm.envOr("FORCE_FUND_AMOUNT", uint256(10_000_000_000));

        vm.startBroadcast();

        ForceSend sender = new ForceSend{value: amount}();
        sender.destroy(adapter);

        vm.stopBroadcast();

        console2.log("Force-funded adapter:", adapter);
        console2.log("Amount:", amount);
    }
}