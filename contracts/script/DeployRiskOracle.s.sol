// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {RiskOracle} from "../src/RiskOracle.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";

/// @notice Deploys Solidity RiskOracle and seeds local lending product score.
///
/// Usage:
///   forge script contracts/script/DeployRiskOracle.s.sol \
///     --rpc-url $ETH_RPC_URL \
///     --private-key $PRIVATE_KEY \
///     --broadcast
contract DeployRiskOracle is Script {
    function run() external {
        bytes32 productId = ProductIds.USDC_HUB_LENDING_V1;

        vm.startBroadcast();

        RiskOracle oracle = new RiskOracle();

        // Seed score so deposits do not hit score=0 gate by default.
        uint256 seededScore = oracle.updateScore(productId, 2_000, 1_000_000, 7_000, 30);

        vm.stopBroadcast();

        console2.log("=== RiskOracle deployed ===");
        console2.log("Address:", address(oracle));
        console2.log("Seeded productId:");
        console2.logBytes32(productId);
        console2.log("Seeded score:", seededScore);
        console2.log("");
        console2.log("Next: set RISK_ORACLE_ADDRESS in your .env and redeploy ConduitRouter.");
    }
}
