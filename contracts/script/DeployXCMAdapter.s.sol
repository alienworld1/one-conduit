// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {XCMAdapter} from "../src/XCMAdapter.sol";
import {ConduitRouter} from "../src/ConduitRouter.sol";
import {ConduitRegistry} from "../src/ConduitRegistry.sol";
import {EscrowVault} from "../src/EscrowVault.sol";
import {PendingReceiptNFT} from "../src/PendingReceiptNFT.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";

/*
 * DeployXCMAdapter — Module 6 deployment script.
 *
 * Deploys XCMAdapter and ConduitRouter v3, wires EscrowVault + PendingReceiptNFT,
 * registers the XCM product in ConduitRegistry, seeds the RiskOracle, and pushes metadata.
 *
 * Usage:
 *   forge script contracts/script/DeployXCMAdapter.s.sol \
 *     --rpc-url $ETH_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 *
 * Required env vars:
 *   REGISTRY_ADDRESS      — ConduitRegistry (Module 2): 0xa5E8c0Bf7b2caf0F9A779D1B32640DC88AC258A2
 *   RISK_ORACLE_ADDRESS   — RiskOracle.sol (Module 4.5): 0x925287C7F2BC699A7874FE66Aacc95da432094B3
 *   ESCROW_VAULT_ADDRESS  — EscrowVault (Module 5): 0xe68C52f6bd8985e321d1C81491608EA0af63C577
 *   RECEIPT_NFT_ADDRESS   — PendingReceiptNFT (Module 5)
 *   MOCK_DOT_ADDRESS      — MockERC20 standing in for DOT
 *   RELAYER_ADDRESS       — Address that will call settle() in Module 7 (deployer OK for now)
 *
 * Optional (defaults to msg.sender if not set):
 *   RELAYER_ADDRESS       — Can be the deployer wallet for testnet.
 *
 * After running, fill in contracts/DEPLOYED_ADDRESSES.md with the logged addresses.
 *
 * IMPORTANT post-deployment verification (run these after broadcast):
 *   cast call $ESCROW_VAULT "adapter()(address)" --rpc-url $ETH_RPC_URL
 *   → Must return XCMAdapter address (NOT address(0))
 *
 *   cast call $RECEIPT_NFT "adapter()(address)" --rpc-url $ETH_RPC_URL
 *   → Must return XCMAdapter address (NOT address(0))
 *
 *   cast call $CONDUIT_REGISTRY "getAllProducts()" --rpc-url $ETH_RPC_URL
 *   → Must return two products (local + XCM)
 *
 * XCM message template:
 *   Produced via Polkadot.js Apps → Developer → Extrinsics → polkadotXcm → execute
 *   on wss://asset-hub-paseo-rpc.n.dwellir.com. Encoded call data:
 *     0x1f03050800040000000700e40b54020d010000010100
 *       e68c52f6bd8985e321d1c81491608ea0af63c577eeeeeeeeeeeeeeeeeeeeeeee0000
 *   Strip first 2 bytes (pallet+call index 0x1f03) and trailing 0x0000 maxWeight
 *   to get raw VersionedXcm SCALE bytes.
 *   Template encodes: WithdrawAsset(1 DOT) + DepositAsset(→ EscrowVault AccountId32).
 *   Fixed 1 DOT amount — see XCMAdapter.sol file-level comment for the mismatch disclosure.
 */
contract DeployXCMAdapter is Script {
    // ── Pre-encoded XCM message template ─────────────────────────────────────
    //
    // VersionedXcm::V5 [ WithdrawAsset, DepositAsset ]
    //   WithdrawAsset: native asset (parents=0, Here), Fungible(10_000_000_000 = 1 DOT)
    //   DepositAsset:  Wild(All) → EscrowVault AccountId32 on Passet Hub
    //
    // Derivation: encoded call data from Polkadot.js Apps with prefix 0x1f03 stripped.
    // EscrowVault H160 (0xe68C52f6...C577) padded to AccountId32 (20 bytes + 12×0xEE).
    bytes internal constant XCM_TEMPLATE =
        hex"050800040000000700e40b54020d010000010100"
        hex"e68c52f6bd8985e321d1c81491608ea0af63c577"
        hex"eeeeeeeeeeeeeeeeeeeeeeee";

    bytes32 internal constant XCM_PRODUCT_ID = ProductIds.DOT_BIFROST_VDOT_V1;

    function run() external {
        // ── Load env vars ─────────────────────────────────────────────────────
        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        address riskOracleAddress = vm.envAddress("RISK_ORACLE_ADDRESS");
        address escrowVaultAddress = vm.envAddress("ESCROW_VAULT_ADDRESS");
        address receiptNFTAddress = vm.envAddress("RECEIPT_NFT_ADDRESS");
        address mockDOTAddress = vm.envAddress("MOCK_DOT_ADDRESS");

        // Relayer defaults to the deployer — fine for testnet.
        address relayerAddress = vm.envOr("RELAYER_ADDRESS", msg.sender);

        vm.startBroadcast();

        // ── Step 1: Deploy ConduitRouter v3 ──────────────────────────────────
        //
        // v3 adds receiptNFT storage and a real settle() that delegates to adapters.
        // Previous ConduitRouter (v2) had settle() as a NotImplemented stub.
        // The router is stateless — redeploy costs one tx and one address update.
        ConduitRouter routerV3 = new ConduitRouter(
            registryAddress,
            riskOracleAddress
        );
        console2.log("ConduitRouter v3 deployed:", address(routerV3));

        // ── Step 2: Deploy XCMAdapter ─────────────────────────────────────────
        XCMAdapter xcmAdapter = new XCMAdapter(
            escrowVaultAddress,
            receiptNFTAddress,
            relayerAddress,
            mockDOTAddress,
            registryAddress,
            XCM_PRODUCT_ID,
            XCM_TEMPLATE
        );
        console2.log("XCMAdapter deployed:      ", address(xcmAdapter));

        // ── Step 3: Wire EscrowVault → XCMAdapter ─────────────────────────────
        //
        // CRITICAL — most forgettable step. Without this, every deposit() call
        // reverts with Unauthorized inside EscrowVault.onlyAdapter().
        EscrowVault(escrowVaultAddress).setAdapter(address(xcmAdapter));
        console2.log("EscrowVault.setAdapter() called.");

        // ── Step 4: Wire PendingReceiptNFT → XCMAdapter ───────────────────────
        //
        // CRITICAL — equally forgettable. Without this, mint() reverts Unauthorized.
        PendingReceiptNFT(receiptNFTAddress).setAdapter(address(xcmAdapter));
        console2.log("PendingReceiptNFT.setAdapter() called.");

        // ── Step 5: Set receiptNFT on ConduitRouter v3 ───────────────────────
        routerV3.setReceiptNFT(receiptNFTAddress);
        console2.log("ConduitRouter v3.setReceiptNFT() called.");

        // ── Step 6: Register XCM adapter in ConduitRegistry ──────────────────
        ConduitRegistry(registryAddress).registerAdapter(
            XCM_PRODUCT_ID,
            address(xcmAdapter),
            "DOT Bifrost vDOT v1",
            true // isXCM = true
        );
        console2.log("XCM adapter registered in ConduitRegistry.");

        // ── Step 7: Seed RiskOracle for XCM product ───────────────────────────
        //
        // Parameters: apy=800bps, tvl=500_000, util=3000bps, ageDays=15
        // These produce a score ~45 — lower than the local product (~75), reflecting
        // that Bifrost vDOT is a newer/smaller protocol. Discloses the relative risk.
        IRiskOracle(riskOracleAddress).updateScore(
            XCM_PRODUCT_ID,
            800, // apyBps
            500_000, // tvlUSD
            3000, // utilizationBps
            15 // contractAgeDays
        );
        console2.log("RiskOracle seeded for XCM product.");

        // ── Step 8: Push metadata to ConduitRegistry cache ───────────────────
        //
        // Seeds APY/TVL/utilisation in the registry so getAllProducts() returns
        // non-zero values for the XCM product without waiting for a user interaction.
        xcmAdapter.pushMetadata();
        console2.log("pushMetadata() called - registry cache updated.");

        vm.stopBroadcast();

        // ── Output summary ────────────────────────────────────────────────────

        console2.log("");
        console2.log("======================================================");
        console2.log(
            "=== Module 6 Deployed Addresses (update DEPLOYED_ADDRESSES.md) ==="
        );
        console2.log("======================================================");
        console2.log("ConduitRouter (v3):  ", address(routerV3));
        console2.log("XCMAdapter:          ", address(xcmAdapter));
        console2.log("EscrowVault (existing):", escrowVaultAddress);
        console2.log("PendingReceiptNFT (existing):", receiptNFTAddress);
        console2.log("XCM ProductId:       ");
        console2.logBytes32(XCM_PRODUCT_ID);
        console2.log("");
        console2.log("======================================================");
        console2.log("=== Post-Deployment Verification Commands ===");
        console2.log("======================================================");
        console2.log("");
        console2.log("# Verify EscrowVault.adapter() == XCMAdapter");
        console2.log(
            'cast call $ESCROW_VAULT_ADDRESS "adapter()(address)" --rpc-url $ETH_RPC_URL'
        );
        console2.log("");
        console2.log("# Verify PendingReceiptNFT.adapter() == XCMAdapter");
        console2.log(
            'cast call $RECEIPT_NFT_ADDRESS "adapter()(address)" --rpc-url $ETH_RPC_URL'
        );
        console2.log("");
        console2.log("# Verify two products now registered");
        console2.log(
            'cast call $REGISTRY_ADDRESS "getAllProducts()" --rpc-url $ETH_RPC_URL'
        );
        console2.log("");
        console2.log("# Mint mock DOT to your wallet");
        console2.log(
            'cast send $MOCK_DOT_ADDRESS "mint(address,uint256)" $YOUR_ADDRESS 10000000000000 \\'
        );
        console2.log("  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
        console2.log("");
        console2.log("# Approve ConduitRouter v3 and do Phase 1 deposit");
        console2.log(
            'cast send $MOCK_DOT_ADDRESS "approve(address,uint256)" <ROUTER_V3> 10000000000000 \\'
        );
        console2.log("  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
        console2.log("");
        console2.log(
            'cast send <ROUTER_V3> "deposit(bytes32,uint256,uint256)" \\'
        );
        console2.log("  <XCM_PRODUCT_ID_BYTES32> 1000000000000 0 \\");
        console2.log("  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
        console2.log("");
        console2.log("# After deposit - verify escrow, NFT, and event");
        console2.log(
            'cast call $ESCROW_VAULT_ADDRESS "getBalance(uint256)(uint256)" 1 --rpc-url $ETH_RPC_URL'
        );
        console2.log(
            'cast call $RECEIPT_NFT_ADDRESS "ownerOf(uint256)(address)" 1 --rpc-url $ETH_RPC_URL'
        );
        console2.log("");
        console2.log(
            "# Open the deposit tx in Blockscout - look for internal call to:"
        );
        console2.log(
            "# 0x00000000000000000000000000000000000a0000 (XCM precompile)"
        );
        console2.log("# That call is Demo Scene 3.");
        console2.log("");
        console2.log("XCM template keccak256:");
        console2.logBytes32(keccak256(XCM_TEMPLATE));
    }
}
