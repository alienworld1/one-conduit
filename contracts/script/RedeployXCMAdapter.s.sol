// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ConduitRegistry} from "../src/ConduitRegistry.sol";
import {ConduitRouter} from "../src/ConduitRouter.sol";
import {EscrowVault} from "../src/EscrowVault.sol";
import {PendingReceiptNFT} from "../src/PendingReceiptNFT.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {XCMAdapter} from "../src/XCMAdapter.sol";
import {IRiskOracle} from "../src/interfaces/IRiskOracle.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";

/*
 * WHAT IS REUSED (not redeployed):
 *   - RiskOracle      at RISK_ORACLE_ADDRESS (scores persist by productId)
 *   - MockERC20/mUSDC at MUSDC_ADDRESS        (existing token, no state dependency)
 *   - MockLendingPool at LENDING_POOL_ADDRESS  (existing pool, no state dependency)
 *   - LocalLendingAdapter at LOCAL_ADAPTER_ADDRESS (existing adapter)
 *
 * WHAT IS DEPLOYED FRESH:
 *   - ConduitRegistry (v2 -- clean slate, no stale productId entries)
 *   - EscrowVault     (fresh, adapter slot available)
 *   - PendingReceiptNFT (fresh, adapter slot available)
 *   - MockERC20/mDOT  (fresh ERC20 stand-in for DOT)
 *   - XCMAdapter      (correct XCM template, includes setXcmTemplate())
 *   - ConduitRouter   (v3 -- points at new registry; immutable registry field)
 *
 */
contract RedeployXCMAdapter is Script {
    bytes internal constant XCM_TEMPLATE =
        hex"050800040000000700e40b54020d010000010100"
        hex"e68c52f6bd8985e321d1c81491608ea0af63c577"
        hex"eeeeeeeeeeeeeeeeeeeeeeee";

    bytes32 internal constant LOCAL_PRODUCT = ProductIds.USDC_HUB_LENDING_V1;
    bytes32 internal constant XCM_PRODUCT = ProductIds.DOT_BIFROST_VDOT_V1;
    uint256 internal constant DEMO_MINT_AMOUNT = 10_000_000_000_000; // 1,000 DOT @ 10 decimals

    function run() external {
        // ── Load required env vars ────────────────────────────────────────────
        address riskOracleAddress = vm.envAddress("RISK_ORACLE_ADDRESS");
        vm.envAddress("MUSDC_ADDRESS");
        vm.envAddress("LENDING_POOL_ADDRESS");
        address localAdapterAddress = vm.envAddress("LOCAL_ADAPTER_ADDRESS");
        address relayerAddress = vm.envOr("RELAYER_ADDRESS", msg.sender);

        vm.startBroadcast();

        // ── Step 1: Deploy fresh Mock DOT ERC20 ──────────────────────────────
        MockERC20 mockDOT = new MockERC20("Mock DOT", "mDOT");
        console2.log("MockERC20/mDOT (fresh):  ", address(mockDOT));

        // ── Step 2: Deploy fresh ConduitRegistry ─────────────────────────────
        //
        // Previous registry (0xa5E8...) blocked re-registration of DOT:BIFROST:vdot-v1
        // because productAlreadyRegistered is checked even for deactivated products.
        // This fresh registry starts with zero products.
        ConduitRegistry registry = new ConduitRegistry();
        console2.log("ConduitRegistry (v2):    ", address(registry));

        // ── Step 3: Register LocalLendingAdapter in new registry ──────────────
        //
        // Reuses the existing deployed LocalLendingAdapter -- no need to redeploy it.
        // The adapter's internal registry pointer still points at the old registry, but
        // we can push metadata manually from the owner (this script) below.
        registry.registerAdapter(
            LOCAL_PRODUCT,
            localAdapterAddress,
            "USDC Hub Lending v1",
            false
        );
        console2.log("LocalLendingAdapter re-registered for LOCAL_PRODUCT.");

        // Seed LOCAL product metadata manually since LocalLendingAdapter.pushMetadata()
        // calls the old registry. Using known live pool values here.
        // Adjust apyBps/tvlUSD/utilizationBps to match current pool state if needed.
        registry.pushMetadata(LOCAL_PRODUCT, 500, 0, 5000);
        console2.log("LOCAL product metadata seeded in new registry.");

        // ── Step 4: Deploy fresh EscrowVault ─────────────────────────────────
        //
        // Previous vault's adapter slot was consumed by the wrong XCMAdapter.
        // EscrowVault.setAdapter() is a one-time setter -- must deploy fresh.
        EscrowVault vault = new EscrowVault();
        console2.log("EscrowVault (v2):        ", address(vault));

        // ── Step 5: Deploy fresh PendingReceiptNFT ───────────────────────────
        //
        // Same reason as EscrowVault -- adapter slot already consumed.
        PendingReceiptNFT nft = new PendingReceiptNFT();
        console2.log("PendingReceiptNFT (v2):  ", address(nft));

        // ── Step 6: Deploy XCMAdapter with correct template ──────────────────
        //
        // CRITICAL: XCM_TEMPLATE is 52 bytes -- the pure VersionedXcm SCALE bytes.
        // It does NOT include:
        //   - 0x1f03 prefix (polkadotXcm pallet+call index)
        //   - 0x0000 suffix (maxWeight Weight{0,0} from the extrinsic second parameter)
        // Passing either extra bytes causes "Invalid message format" from the precompile.
        XCMAdapter xcmAdapter = new XCMAdapter(
            address(vault),
            address(nft),
            relayerAddress,
            address(mockDOT),
            address(registry), // new registry
            XCM_PRODUCT,
            XCM_TEMPLATE
        );
        console2.log("XCMAdapter (v2):         ", address(xcmAdapter));

        // ── Step 7: Wire EscrowVault -> XCMAdapter ────────────────────────────
        //
        // MUST be done before any deposit() call or it reverts Unauthorized.
        vault.setAdapter(address(xcmAdapter));
        console2.log("EscrowVault.setAdapter() -> XCMAdapter: OK");

        // ── Step 8: Wire PendingReceiptNFT -> XCMAdapter ─────────────────────
        //
        // MUST be done before any deposit() call or it reverts Unauthorized.
        nft.setAdapter(address(xcmAdapter));
        console2.log("PendingReceiptNFT.setAdapter() -> XCMAdapter: OK");

        // ── Step 9: Register XCMAdapter in new registry ───────────────────────
        registry.registerAdapter(
            XCM_PRODUCT,
            address(xcmAdapter),
            "DOT Bifrost vDOT v1",
            true // isXCM = true
        );
        console2.log("XCMAdapter registered for XCM_PRODUCT.");

        // ── Step 10: Seed RiskOracle scores ───────────────────────────────────
        //
        // RiskOracle stores scores by productId (bytes32) -- not by registry or router address.
        // Re-seeding ensures both products have fresh scores in case the oracle was reset.
        // LOCAL product: apy=500bps, tvl=1M, util=7000bps, age=30 days -> score ~75
        IRiskOracle(riskOracleAddress).updateScore(
            LOCAL_PRODUCT,
            500,
            1_000_000,
            7000,
            30
        );
        console2.log("RiskOracle seeded: LOCAL_PRODUCT score ~75");
        // XCM product: apy=800bps, tvl=500k, util=3000bps, age=15 days -> score ~45
        IRiskOracle(riskOracleAddress).updateScore(
            XCM_PRODUCT,
            800,
            500_000,
            3000,
            15
        );
        console2.log("RiskOracle seeded: XCM_PRODUCT score ~45");

        // ── Step 11: Push XCM product metadata to new registry ───────────────
        //
        // xcmAdapter.pushMetadata() sends to the new registry (passed in constructor).
        xcmAdapter.pushMetadata();
        console2.log("XCMAdapter.pushMetadata() -> new registry: OK");

        // ── Step 12: Deploy ConduitRouter v3 pointing at new registry ─────────
        //
        // ConduitRouter has immutable registry -- must redeploy when registry changes.
        // setReceiptNFT() called immediately so settle() is operational from the start.
        ConduitRouter router = new ConduitRouter(
            address(registry),
            riskOracleAddress
        );
        router.setReceiptNFT(address(nft));
        console2.log("ConduitRouter (v3, new): ", address(router));
        console2.log("ConduitRouter.setReceiptNFT() -> PendingReceiptNFT: OK");

        // ── Step 13: Pre-fund deployer and pre-approve router for demo deposits ─────────
        //
        // This prevents the common failure where users approve/mint on a stale token address.
        // The token/router pair used here is exactly what was deployed above.
        mockDOT.mint(msg.sender, DEMO_MINT_AMOUNT);
        mockDOT.approve(address(router), type(uint256).max);
        console2.log("Demo funding: minted mDOT to deployer:", DEMO_MINT_AMOUNT);
        console2.log("Demo funding: approved router for mDOT: unlimited");

        vm.stopBroadcast();

        // ── Verify template (sanity) ──────────────────────────────────────────
        bytes memory storedTemplate = xcmAdapter.xcmMessageTemplate();
        require(
            storedTemplate.length == 52,
            "template length wrong: expected 52 bytes"
        );
        // Last two bytes must NOT be 0x0000 (the maxWeight suffix bug).
        require(
            uint8(storedTemplate[50]) != 0x00 ||
                uint8(storedTemplate[51]) != 0x00,
            "template ends with 0x0000: maxWeight suffix still present"
        );
        console2.log(
            "XCM template sanity check: PASSED (52 bytes, no 0x0000 suffix)"
        );

        // ── Print summary ─────────────────────────────────────────────────────
        console2.log("");
        console2.log(
            "============================================================"
        );
        console2.log(
            "=== RedeployModule6 complete -- update DEPLOYED_ADDRESSES.md ==="
        );
        console2.log(
            "============================================================"
        );
        console2.log("ConduitRegistry (v2):    ", address(registry));
        console2.log("EscrowVault (v2):        ", address(vault));
        console2.log("PendingReceiptNFT (v2):  ", address(nft));
        console2.log("XCMAdapter (v2):         ", address(xcmAdapter));
        console2.log("ConduitRouter (v3, new): ", address(router));
        console2.log("RiskOracle (unchanged):  ", riskOracleAddress);
        console2.log("MockDOT (deployed):      ", address(mockDOT));
        console2.log("LocalLendingAdapter (unchanged):", localAdapterAddress);
        console2.log("");
        console2.log("XCM ProductId:");
        console2.logBytes32(XCM_PRODUCT);
        console2.log("XCM template keccak256:");
        console2.logBytes32(keccak256(XCM_TEMPLATE));
        console2.log("");
        console2.log(
            "============================================================"
        );
        console2.log("=== Next: update frontend lib/contracts.ts ===");
        console2.log("REGISTRY_ADDRESS  =", address(registry));
        console2.log("ROUTER_ADDRESS    =", address(router));
        console2.log("ESCROW_VAULT      =", address(vault));
        console2.log("RECEIPT_NFT       =", address(nft));
        console2.log("XCM_ADAPTER       =", address(xcmAdapter));
        console2.log("");
        console2.log(
            "============================================================"
        );
        console2.log("=== Post-deployment verification ===");
        console2.log(
            "============================================================"
        );
        console2.log("");
        console2.log("# Verify wiring");
        console2.log(
            "cast call <VAULT>  'adapter()(address)' --rpc-url $ETH_RPC_URL"
        );
        console2.log("# -> must equal XCMAdapter address");
        console2.log(
            "cast call <NFT>    'adapter()(address)' --rpc-url $ETH_RPC_URL"
        );
        console2.log("# -> must equal XCMAdapter address");
        console2.log(
            "cast call <ROUTER> 'receiptNFT()(address)' --rpc-url $ETH_RPC_URL"
        );
        console2.log("# -> must equal PendingReceiptNFT address");
        console2.log("");
        console2.log("# Verify two products registered");
        console2.log("cast call <REGISTRY> 'getAllProducts()' --rpc-url $ETH_RPC_URL");
        console2.log("REGISTRY=");
        console2.logAddress(address(registry));
        console2.log("");
        console2.log("# mDOT was already minted and approved in this script.");
        console2.log("# If you want to top up manually:");
        console2.log("MOCK_DOT=");
        console2.logAddress(address(mockDOT));
        console2.log("ROUTER=");
        console2.logAddress(address(router));
        console2.log("cast send <MOCK_DOT> 'mint(address,uint256)' $YOUR_ADDR 10000000000000 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
        console2.log("cast send <MOCK_DOT> 'approve(address,uint256)' <ROUTER> 10000000000000 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
        console2.log("cast send <ROUTER> 'deposit(bytes32,uint256,uint256)'");
        console2.logBytes32(XCM_PRODUCT);
        console2.log("1000000000000 0 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL");
        console2.log("");
        console2.log("# Verify escrow and NFT after deposit");
        console2.log("VAULT=");
        console2.logAddress(address(vault));
        console2.log("cast call <VAULT> 'getBalance(uint256)(uint256)' 1 --rpc-url $ETH_RPC_URL");
        console2.log("# -> must equal 1000000000000");
        console2.log("NFT=");
        console2.logAddress(address(nft));
        console2.log("cast call <NFT> 'ownerOf(uint256)(address)' 1 --rpc-url $ETH_RPC_URL");
        console2.log("# -> must equal your address");
        console2.log("");
        console2.log(
            "# Open deposit tx in Blockscout -- look for internal call to:"
        );
        console2.log(
            "# 0x00000000000000000000000000000000000a0000  <- XCM precompile"
        );
        console2.log("# That is Demo Scene 3.");
    }
}
