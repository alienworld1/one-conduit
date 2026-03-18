// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PendingReceiptNFT.sol";

contract PendingReceiptNFTTest is Test {
    PendingReceiptNFT public nft;

    address public owner = address(this);
    address public adapter = address(0xA1);
    address public alice = address(0xB1);
    address public bob = address(0xB2);

    function setUp() public {
        nft = new PendingReceiptNFT();
    }

    function test_SetAdapter() public {
        nft.setAdapter(adapter);
        assertEq(nft.adapter(), adapter);
    }

    function test_MintAndTransfer() public {
        nft.setAdapter(adapter);

        PendingReceiptNFT.ReceiptData memory data = PendingReceiptNFT.ReceiptData({
            productId: bytes32(uint256(1)),
            amount: 100,
            originalDepositor: alice,
            dispatchBlock: 1234,
            settled: false
        });

        vm.prank(adapter);
        uint256 tokenId = nft.mint(alice, data);

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.nextTokenId(), 2);

        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        assertEq(nft.ownerOf(tokenId), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
    }

    function test_Burn() public {
        nft.setAdapter(adapter);

        PendingReceiptNFT.ReceiptData memory data = PendingReceiptNFT.ReceiptData({
            productId: bytes32(uint256(1)),
            amount: 100,
            originalDepositor: alice,
            dispatchBlock: 1234,
            settled: true // Set to true to satisfy NotSettledBeforeBurn
        });

        // 1. Mint by adapter
        vm.prank(adapter);
        uint256 tokenId = nft.mint(alice, data);
        assertEq(nft.balanceOf(alice), 1);

        // 2. Burn by adapter
        vm.prank(adapter);
        nft.burn(tokenId);

        assertEq(nft.balanceOf(alice), 0);
        vm.expectRevert(abi.encodeWithSelector(PendingReceiptNFT.TokenNotFound.selector, tokenId));
        nft.ownerOf(tokenId);

        assertTrue(nft.isSettled(tokenId));
    }
}
