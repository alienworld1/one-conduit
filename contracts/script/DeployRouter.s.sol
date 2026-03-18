// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ConduitRouter} from "../src/ConduitRouter.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";

/*
 * DeployRouter — deploys ConduitRouter on Paseo Passet Hub.
 *
 * Usage:
 *   forge script contracts/script/DeployRouter.s.sol \
 *     --rpc-url $ETH_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 *
 * Env vars required:
 *   REGISTRY_ADDRESS     — deployed ConduitRegistry (Module 2)
 *   RISK_ORACLE_ADDRESS  — deployed RiskOracle ink! contract (Module 1)
 *
 * NOTE: Seed score in DeployRiskOracle.s.sol before routing deposits.
 */
contract DeployRouter is Script {
    function run() external {
        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        address riskOracleAddress = vm.envAddress("RISK_ORACLE_ADDRESS");
        bytes32 productId = ProductIds.USDC_HUB_LENDING_V1;

        vm.startBroadcast();
        ConduitRouter router = new ConduitRouter(registryAddress, riskOracleAddress);
        vm.stopBroadcast();

        console2.log("=== ConduitRouter deployed ===");
        console2.log("Address:", address(router));
        console2.log("");
        console2.log("=== Step 1: Verify seeded RiskOracle score ===");
        console2.log("cast call $RISK_ORACLE_ADDRESS \"");
        console2.log("  getScore(bytes32)(uint256)\" \\");
        console2.log("  <PRODUCT_ID_BYTES32> --rpc-url $ETH_RPC_URL");
        console2.log("");
        console2.log("ProductId bytes32 (paste as <PRODUCT_ID_BYTES32>):");
        console2.logBytes32(productId);
        console2.log("");
        console2.log("=== Step 2: Seed RiskOracle if score is zero ===");
        console2.log("cast send $RISK_ORACLE_ADDRESS \\");
        console2.log("  \"updateScore(bytes32,uint256,uint256,uint256,uint256)\" \\");
        console2.log("  <PRODUCT_ID_BYTES32> 2000 1000000 7000 30 \\");
        console2.log("  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
        console2.log("");
        console2.log("=== Step 3: Approve + deposit ===");
        console2.log("cast send $MUSDC \"approve(address,uint256)\" <ROUTER_ADDRESS> 1000000000 \\");
        console2.log("  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
        console2.log("");
        console2.log("cast send <ROUTER_ADDRESS> \"deposit(bytes32,uint256,uint256)\" \\");
        console2.log("  <PRODUCT_ID_BYTES32> 1000000000 50 \\");
        console2.log("  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
    }
}
