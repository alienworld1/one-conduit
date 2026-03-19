// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {XCMAdapter, Settled, InvalidSettlementProof, ReceiptAlreadySettled} from "../src/XCMAdapter.sol";
import {ConduitRouter} from "../src/ConduitRouter.sol";
import {ConduitRegistry} from "../src/ConduitRegistry.sol";
import {EscrowVault} from "../src/EscrowVault.sol";
import {PendingReceiptNFT} from "../src/PendingReceiptNFT.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockRiskOracle} from "./mocks/MockRiskOracle.sol";
import {IXcm} from "../src/interfaces/IXcm.sol";

contract MockXCMPrecompileSettlement {
    function execute(bytes calldata, IXcm.Weight calldata) external {}

    function send(bytes calldata, bytes calldata) external {}

    function weighMessage(bytes calldata) external pure returns (IXcm.Weight memory) {
        return IXcm.Weight(400_000_000, 65_536);
    }
}

contract SettlementTest is Test {
    address internal constant XCM_PRECOMPILE = 0x00000000000000000000000000000000000a0000;

    uint256 internal constant RELAYER_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address internal constant RELAYER_ADDR = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    bytes32 internal constant XCM_PRODUCT_ID = ProductIds.DOT_BIFROST_VDOT_V1;
    bytes internal constant XCM_TEMPLATE = hex"deadbeef";

    uint256 internal constant ONE_DOT = 10_000_000_000;
    uint256 internal constant DEPOSIT_AMOUNT = 1_000 * ONE_DOT;
    uint256 internal constant INITIAL_BALANCE = 10_000 * ONE_DOT;

    address internal constant alice = address(0xA11CE);
    address internal constant bob = address(0xB0B);

    MockERC20 internal mockDOT;
    EscrowVault internal vault;
    PendingReceiptNFT internal nft;
    XCMAdapter internal xcmAdapter;

    ConduitRegistry internal registry;
    MockRiskOracle internal oracle;
    ConduitRouter internal router;

    function setUp() public {
        mockDOT = new MockERC20("Mock DOT", "mDOT");
        vault = new EscrowVault();
        nft = new PendingReceiptNFT();

        xcmAdapter = new XCMAdapter(
            address(vault),
            address(nft),
            RELAYER_ADDR,
            address(mockDOT),
            address(0),
            XCM_PRODUCT_ID,
            XCM_TEMPLATE
        );

        vault.setAdapter(address(xcmAdapter));
        nft.setAdapter(address(xcmAdapter));

        MockXCMPrecompileSettlement mockPrecompile = new MockXCMPrecompileSettlement();
        vm.etch(XCM_PRECOMPILE, address(mockPrecompile).code);

        registry = new ConduitRegistry();
        oracle = new MockRiskOracle();
        router = new ConduitRouter(address(registry), address(oracle));
        registry.registerAdapter(XCM_PRODUCT_ID, address(xcmAdapter), "DOT Bifrost vDOT v1", true);
        oracle.setScore(XCM_PRODUCT_ID, 80);
        router.setReceiptNFT(address(nft));

        mockDOT.mint(alice, INITIAL_BALANCE);
        mockDOT.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        mockDOT.approve(address(xcmAdapter), type(uint256).max);

        vm.prank(alice);
        mockDOT.approve(address(router), type(uint256).max);
    }

    function _depositViaAdapter(address user, uint256 amount) internal returns (uint256 receiptId) {
        vm.prank(user);
        receiptId = xcmAdapter.deposit(amount, user);
    }

    function _depositViaRouter(address user, uint256 amount) internal returns (uint256 receiptId) {
        vm.prank(user);
        router.deposit(XCM_PRODUCT_ID, amount, 0);
        receiptId = nft.nextTokenId() - 1;
    }

    function _makeProof(uint256 receiptId) internal view returns (bytes memory) {
        return _makeProofWithChainAndAdapter(receiptId, block.chainid, address(xcmAdapter), RELAYER_KEY);
    }

    function _makeProofWithChainAndAdapter(
        uint256 receiptId,
        uint256 chainId_,
        address adapterAddress,
        uint256 key
    ) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked("OneConduit:settle:", chainId_, adapterAddress, receiptId)
        );
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    function test_settle_success() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);

        xcmAdapter.settle(1, _makeProof(1));

        assertEq(mockDOT.balanceOf(alice), INITIAL_BALANCE, "alice should receive released funds");
        assertEq(mockDOT.balanceOf(address(vault)), 0, "vault should be emptied after settlement");

        (, , , , bool settled) = nft.receipts(1);
        assertTrue(settled, "receipt should be marked settled");
    }

    function test_settle_viaRouter() public {
        _depositViaRouter(alice, DEPOSIT_AMOUNT);

        router.settle(1, _makeProof(1));

        assertEq(mockDOT.balanceOf(alice), INITIAL_BALANCE, "router delegation should settle receipt");
        (, , , , bool settled) = nft.receipts(1);
        assertTrue(settled, "receipt should be marked settled via router");
    }

    function test_settle_transferThenSettle_endToEnd() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        uint256 aliceBefore = mockDOT.balanceOf(alice);
        uint256 bobBefore = mockDOT.balanceOf(bob);

        xcmAdapter.settle(1, _makeProof(1));

        assertEq(mockDOT.balanceOf(bob), bobBefore + DEPOSIT_AMOUNT, "bob should receive settled funds");
        assertEq(mockDOT.balanceOf(alice), aliceBefore, "alice balance should remain unchanged");
        assertTrue(nft.isSettled(1), "receipt should be settled");
    }

    function test_settle_wrongSigner() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);
        bytes memory wrongSignerProof = _makeProofWithChainAndAdapter(1, block.chainid, address(xcmAdapter), uint256(0xB0B));

        vm.expectRevert(abi.encodeWithSelector(InvalidSettlementProof.selector, uint256(1)));
        xcmAdapter.settle(1, wrongSignerProof);
    }

    function test_settle_wrongReceiptId() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(InvalidSettlementProof.selector, uint256(2)));
        xcmAdapter.settle(2, _makeProof(1));
    }

    function test_settle_wrongContract() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);
        bytes memory proof = _makeProofWithChainAndAdapter(1, block.chainid, address(router), RELAYER_KEY);

        vm.expectRevert(abi.encodeWithSelector(InvalidSettlementProof.selector, uint256(1)));
        xcmAdapter.settle(1, proof);
    }

    function test_settle_wrongChainId() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);
        bytes memory proof = _makeProofWithChainAndAdapter(1, block.chainid + 1, address(xcmAdapter), RELAYER_KEY);

        vm.expectRevert(abi.encodeWithSelector(InvalidSettlementProof.selector, uint256(1)));
        xcmAdapter.settle(1, proof);
    }

    function test_settle_shortProof() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(InvalidSettlementProof.selector, uint256(1)));
        xcmAdapter.settle(1, hex"00");
    }

    function test_settle_emptyProof() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(InvalidSettlementProof.selector, uint256(1)));
        xcmAdapter.settle(1, "");
    }

    function test_settle_doubleSettle() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);

        xcmAdapter.settle(1, _makeProof(1));

        vm.expectRevert(abi.encodeWithSelector(ReceiptAlreadySettled.selector, uint256(1)));
        xcmAdapter.settle(1, _makeProof(1));
    }

    function test_settle_nftBurned() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);
        xcmAdapter.settle(1, _makeProof(1));

        vm.expectRevert(abi.encodeWithSelector(PendingReceiptNFT.TokenNotFound.selector, uint256(1)));
        nft.ownerOf(1);
    }

    function test_settle_receiptMetadataPreserved() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);
        xcmAdapter.settle(1, _makeProof(1));

        (bytes32 productId, uint256 amount, address depositor, uint256 dispatchBlock, bool settled) = nft.receipts(1);
        assertEq(productId, XCM_PRODUCT_ID);
        assertEq(amount, DEPOSIT_AMOUNT);
        assertEq(depositor, alice);
        assertGt(dispatchBlock, 0);
        assertTrue(settled);
    }

    function test_settle_escrowReleased() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);
        xcmAdapter.settle(1, _makeProof(1));

        EscrowVault.Escrow memory escrow = vault.getEscrow(1);
        assertEq(escrow.amount, DEPOSIT_AMOUNT);
        assertTrue(escrow.released, "escrow should be marked released");
    }

    function test_settle_emitsCorrectEvent() public {
        _depositViaAdapter(alice, DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit Settled(alice, 1, DEPOSIT_AMOUNT);

        xcmAdapter.settle(1, _makeProof(1));
    }
}
