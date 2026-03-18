// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowVault.sol";
import "../src/mocks/MockERC20.sol";

contract EscrowVaultTest is Test {
    EscrowVault public vault;
    MockERC20 public token;

    address public owner = address(this);
    address public adapter = address(0xA1);
    address public user = address(0xB1);

    function setUp() public {
        vault = new EscrowVault();
        token = new MockERC20("Test Token", "TEST");
    }

    function test_SetAdapter() public {
        vault.setAdapter(adapter);
        assertEq(vault.adapter(), adapter);

        vm.expectRevert(EscrowVault.AdapterAlreadySet.selector);
        vault.setAdapter(address(0xA2));
    }

    function test_DepositAndRelease() public {
        vault.setAdapter(adapter);

        uint256 amount = 1000;
        token.mint(adapter, amount);

        vm.startPrank(adapter);
        token.approve(address(vault), amount);

        vault.deposit(1, address(token), amount);

        assertEq(vault.getBalance(1), amount);
        assertEq(token.balanceOf(address(vault)), amount);

        vault.release(1, user);

        assertEq(token.balanceOf(user), amount);
        assertTrue(vault.getEscrow(1).released);

        vm.expectRevert(abi.encodeWithSelector(EscrowVault.AlreadyReleased.selector, 1));
        vault.release(1, user);
        vm.stopPrank();
    }

    function test_OnlyAdapterCanDeposit() public {
        vault.setAdapter(adapter);

        vm.expectRevert(EscrowVault.Unauthorized.selector);
        vault.deposit(1, address(token), 100);
    }

    function test_UnconfiguredVaultReverts() public {
        // Vault has no adapter set
        vm.startPrank(adapter);
        vm.expectRevert(EscrowVault.Unauthorized.selector);
        vault.deposit(1, address(token), 100);
        vm.stopPrank();
    }
}
