// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Lock} from "../src/Lock.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract TimeLockTest is Test {
    Lock internal token;
    TimeLock internal vault;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        vm.warp(1_000);
        token = new Lock();
        vault = new TimeLock(address(token));
        token.approve(address(vault), type(uint256).max);
    }

    function testDepositAndExactBoundaryWithdrawalEvents() public {
        vm.expectEmit(true, true, true, true, address(vault));
        emit TimeLock.Locked(0, address(this), alice, 100, 2_000);
        assertEq(vault.lock(alice, 100, 2_000), 0);
        TimeLock.Deposit memory d = vault.getLock(0);
        assertEq(d.depositor, address(this));
        assertEq(d.beneficiary, alice);
        assertEq(d.amount, 100);
        assertEq(d.unlockTime, 2_000);
        assertFalse(d.withdrawn);
        vm.warp(1_999);
        vm.prank(alice);
        vm.expectRevert(TimeLock.StillLocked.selector);
        vault.withdraw(0);
        vm.warp(2_000);
        vm.expectEmit(true, true, false, true, address(vault));
        emit TimeLock.Withdrawn(0, alice, 100);
        vm.prank(alice);
        vault.withdraw(0);
        assertTrue(vault.getLock(0).withdrawn);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(vault.totalLocked(), 0);
        vm.prank(alice);
        vm.expectRevert(TimeLock.AlreadyWithdrawn.selector);
        vault.withdraw(0);
    }

    function testOnlyBeneficiaryCanWithdrawOrExtend() public {
        vault.lock(alice, 100, 2_000);
        vm.warp(2_000);
        vm.expectRevert(TimeLock.NotBeneficiary.selector);
        vault.withdraw(0);
        vm.expectRevert(TimeLock.NotBeneficiary.selector);
        vault.extendLock(0, 3_000);
        vm.prank(bob);
        vm.expectRevert(TimeLock.NotBeneficiary.selector);
        vault.withdraw(0);
        vm.prank(bob);
        vm.expectRevert(TimeLock.NotBeneficiary.selector);
        vault.extendLock(0, 3_000);
    }

    function testExtensionCannotShortenAndDelaysWithdrawal() public {
        vault.lock(alice, 100, 2_000);
        vm.startPrank(alice);
        vm.expectRevert(TimeLock.InvalidUnlockTime.selector);
        vault.extendLock(0, 1_999);
        vm.expectRevert(TimeLock.InvalidUnlockTime.selector);
        vault.extendLock(0, 2_000);
        vm.expectEmit(true, false, false, true, address(vault));
        emit TimeLock.LockExtended(0, 2_000, 3_000);
        vault.extendLock(0, 3_000);
        vm.warp(2_000);
        vm.expectRevert(TimeLock.StillLocked.selector);
        vault.withdraw(0);
        vm.warp(3_001);
        vm.expectRevert(TimeLock.InvalidUnlockTime.selector);
        vault.extendLock(0, 3_001);
        vault.extendLock(0, 4_000);
        vm.warp(4_001);
        vault.withdraw(0);
        vm.expectRevert(TimeLock.AlreadyWithdrawn.selector);
        vault.extendLock(0, 5_000);
        vm.stopPrank();
    }

    function testEnumerationRetainsHistoryAndSeparatesBeneficiaries() public {
        vault.lock(alice, 10, 2_000);
        vault.lock(bob, 20, 3_000);
        vault.lock(alice, 30, 4_000);
        assertEq(vault.lockCount(alice), 2);
        assertEq(vault.lockCount(bob), 1);
        assertEq(vault.lockCount(address(0)), 0);
        assertEq(vault.lockIdAt(alice, 0), 0);
        assertEq(vault.lockIdAt(bob, 0), 1);
        assertEq(vault.lockIdAt(alice, 1), 2);
        vm.expectRevert();
        vault.lockIdAt(alice, 2);
        vm.warp(4_000);
        vm.prank(alice);
        vault.withdraw(2);
        assertEq(vault.lockCount(alice), 2);
        assertEq(vault.lockIdAt(alice, 1), 2);
        assertEq(vault.totalLocked(), 30);
        assertEq(token.balanceOf(address(vault)), 30);
    }

    function testInvalidConstructorAndInputs() public {
        vm.expectRevert(TimeLock.InvalidToken.selector);
        new TimeLock(address(0));
        vm.expectRevert(TimeLock.InvalidToken.selector);
        new TimeLock(alice);
        vm.expectRevert(TimeLock.InvalidBeneficiary.selector);
        vault.lock(address(0), 1, 2_000);
        vm.expectRevert(TimeLock.InvalidBeneficiary.selector);
        vault.lock(address(vault), 1, 2_000);
        vm.expectRevert(TimeLock.InvalidAmount.selector);
        vault.lock(alice, 0, 2_000);
        vm.expectRevert(TimeLock.InvalidUnlockTime.selector);
        vault.lock(alice, 1, 1_000);
        vm.expectRevert(TimeLock.InvalidUnlockTime.selector);
        vault.lock(alice, 1, 999);
        vm.expectRevert(TimeLock.UnknownLock.selector);
        vault.getLock(0);
        vm.expectRevert(TimeLock.UnknownLock.selector);
        vault.withdraw(0);
        vm.expectRevert(TimeLock.UnknownLock.selector);
        vault.extendLock(0, 2_000);
        assertEq(vault.nextLockId(), 0);
    }

    function testPermissionAndBalanceFailureRollBackDeposit() public {
        token.approve(address(vault), 0);
        vm.expectRevert(Lock.InsufficientAllowance.selector);
        vault.lock(alice, 10, 2_000);
        token.approve(address(vault), 9);
        vm.expectRevert(Lock.InsufficientAllowance.selector);
        vault.lock(alice, 10, 2_000);
        vm.startPrank(bob);
        token.approve(address(vault), 10);
        vm.expectRevert(Lock.InsufficientBalance.selector);
        vault.lock(alice, 10, 2_000);
        vm.stopPrank();
        assertEq(vault.nextLockId(), 0);
        assertEq(vault.lockCount(alice), 0);
        assertEq(vault.totalLocked(), 0);
        assertEq(token.allowance(bob, address(vault)), 10);
    }

    function testSelfDepositAndDirectDonation() public {
        vault.lock(address(this), 10, 2_000);
        token.transfer(address(vault), 7);
        vm.warp(2_000);
        vault.withdraw(0);
        assertEq(vault.totalLocked(), 0);
        assertEq(token.balanceOf(address(vault)), 7);
    }

    function testFuzzMultipleLocksConserveFunds(uint96 a, uint96 b, uint32 delay) public {
        uint256 first = bound(uint256(a), 1, 1e26);
        uint256 second = bound(uint256(b), 1, 1e26);
        uint256 maturity = block.timestamp + bound(uint256(delay), 1, 36500 days);
        vault.lock(alice, first, maturity);
        vault.lock(alice, second, maturity + 1);
        assertEq(vault.totalLocked(), first + second);
        assertEq(token.balanceOf(address(vault)), first + second);
        vm.warp(maturity);
        vm.prank(alice);
        vault.withdraw(0);
        assertEq(vault.totalLocked(), second);
        vm.prank(alice);
        vm.expectRevert(TimeLock.StillLocked.selector);
        vault.withdraw(1);
        vm.warp(maturity + 1);
        vm.prank(alice);
        vault.withdraw(1);
        assertEq(vault.totalLocked(), 0);
        assertEq(token.balanceOf(alice), first + second);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice), token.totalSupply());
    }
}
