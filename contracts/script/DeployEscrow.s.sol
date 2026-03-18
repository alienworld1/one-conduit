// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/EscrowVault.sol";
import "../src/PendingReceiptNFT.sol";

contract DeployEscrow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EscrowVault vault = new EscrowVault();
        console.log("EscrowVault deployed at:", address(vault));

        PendingReceiptNFT nft = new PendingReceiptNFT();
        console.log("PendingReceiptNFT deployed at:", address(nft));

        vm.stopBroadcast();
    }
}
