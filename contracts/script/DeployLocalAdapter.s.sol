// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2}       from "forge-std/Script.sol";
import {MockERC20}              from "../src/mocks/MockERC20.sol";
import {MockLendingPool}        from "../src/MockLendingPool.sol";
import {LocalLendingAdapter}    from "../src/LocalLendingAdapter.sol";
import {ConduitRegistry}        from "../src/ConduitRegistry.sol";
import {ProductIds}             from "../src/libraries/ProductIds.sol";

/*
 * DeployLocalAdapter — deploys MockERC20 (USDC stand-in), MockLendingPool,
 * LocalLendingAdapter, registers it in ConduitRegistry, and calls pushMetadata.
 *
 * Usage:
 *   forge script contracts/script/DeployLocalAdapter.s.sol \
 *     --rpc-url $ETH_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 *
 * Env vars required:
 *   REGISTRY_ADDRESS  — deployed ConduitRegistry address (from Module 2)
 *
 * After deployment, fill in contracts/DEPLOYED_ADDRESSES.md with the logged addresses.
 *
 * Call setAnnualRate(2000) separately for demo visibility (20% APY = $0.0038 per 10 min).
 */
contract DeployLocalAdapter is Script {
    function run() external {
        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        bytes32 productId       = ProductIds.USDC_HUB_LENDING_V1;

        vm.startBroadcast();

        // 1. Deploy MockERC20 as canonical USDC stand-in.
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC");

        // 2. Deploy MockLendingPool (5% APY default; use setAnnualRate for demo).
        //    MockYieldToken is deployed inside MockLendingPool's constructor.
        MockLendingPool pool = new MockLendingPool(address(mockUSDC), 500);

        // 3. Deploy LocalLendingAdapter.
        LocalLendingAdapter adapter = new LocalLendingAdapter(
            address(pool),
            registryAddress,
            productId
        );

        // 4. Register adapter in ConduitRegistry.
        ConduitRegistry(registryAddress).registerAdapter(
            productId,
            address(adapter),
            "USDC Hub Lending v1",
            false
        );

        // 5. Push initial metadata — seeds APY/TVL in the registry.
        adapter.pushMetadata();

        // 6. Mint mock USDC to the deployer for testing.
        mockUSDC.mint(msg.sender, 100_000e6); // 100,000 mUSDC

        vm.stopBroadcast();

        // Log all addresses for DEPLOYED_ADDRESSES.md.
        console2.log("=== Module 3 Deployed Addresses ===");
        console2.log("MockERC20 (mUSDC):          ", address(mockUSDC));
        console2.log("MockYieldToken (cYLD):      ", pool.yieldToken());
        console2.log("MockLendingPool:             ", address(pool));
        console2.log("LocalLendingAdapter:         ", address(adapter));
        console2.log("");
        console2.log("ConduitRegistry (existing):  ", registryAddress);
        console2.log("ProductId:                   ");
        console2.logBytes32(productId);
        console2.log("");
        console2.log("Next: call setAnnualRate(2000) on MockLendingPool for demo APY.");
        console2.log("  cast send <POOL> \"setAnnualRate(uint256)\" 2000 --private-key $PK --rpc-url $RPC");
    }
}
