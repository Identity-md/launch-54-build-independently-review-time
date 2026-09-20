// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {AdversarialToken} from "./mocks/AdversarialToken.sol";

contract AdversarialTest is Test {
    AdversarialToken internal token;
    TimeLock internal vault;

    function setUp() public {
        vm.warp(1_000);
        token = new AdversarialToken();
        vault = new TimeLock(address(token));
        token.approve(address(vault), type(uint256).max);
    }

    function testIncomingFalseRevertAndMalformedReturnAreAtomic() public {
        for (uint256 mode = 1; mode <= 3; ++mode) {
            token.configure(mode, address(0), "");
            if (mode == 1) vm.expectRevert(TimeLock.TransferFailed.selector);
            else if (mode == 2) vm.expectRevert(AdversarialToken.TokenDenied.selector);
            else vm.expectRevert();
            vault.lock(address(this), 10, 2_000);
            assertEq(vault.nextLockId(), 0);
            assertEq(vault.lockCount(address(this)), 0);
            assertEq(vault.totalLocked(), 0);
            assertEq(token.balanceOf(address(vault)), 0);
            assertEq(token.balanceOf(address(this)), 1e27);
            assertEq(token.allowance(address(this), address(vault)), type(uint256).max);
        }
        token.configure(0, address(0), "");
        assertEq(vault.lock(address(this), 10, 2_000), 0);
    }

    function testOutgoingFalseRevertAndMalformedReturnAreRetryable() public {
        vault.lock(address(this), 10, 2_000);
        vm.warp(2_000);
        for (uint256 mode = 1; mode <= 3; ++mode) {
            token.configure(mode, address(0), "");
            if (mode == 1) vm.expectRevert(TimeLock.TransferFailed.selector);
            else if (mode == 2) vm.expectRevert(AdversarialToken.TokenDenied.selector);
            else vm.expectRevert();
            vault.withdraw(0);
            assertFalse(vault.getLock(0).withdrawn);
            assertEq(vault.totalLocked(), 10);
            assertEq(token.balanceOf(address(vault)), 10);
            assertEq(token.balanceOf(address(this)), 1e27 - 10);
        }
        token.configure(0, address(0), "");
        vault.withdraw(0);
        assertEq(token.balanceOf(address(this)), 1e27);
        assertEq(vault.totalLocked(), 0);
    }

    function testReentryDuringDepositBlocksAllMutations() public {
        // Token is beneficiary of a matured lock: its withdrawal/extension would be authorized
        // without the guard, so this proves cross-function protection as well as permissions.
        vault.lock(address(token), 10, 1_001);
        vm.warp(1_001);
        bytes[3] memory attacks = [
            abi.encodeCall(TimeLock.withdraw, (0)),
            abi.encodeCall(TimeLock.extendLock, (0, 3_000)),
            abi.encodeCall(TimeLock.lock, (address(token), 1, 3_000))
        ];
        for (uint256 i; i < attacks.length; ++i) {
            token.configure(0, address(vault), attacks[i]);
            vault.lock(address(this), 10, 2_000);
            assertFalse(token.callbackSucceeded());
            assertEq(token.callbackResult(), abi.encodeWithSelector(TimeLock.Reentrancy.selector));
        }
        assertEq(token.callbackCount(), 3);
        assertEq(vault.totalLocked(), 40);
        assertEq(token.balanceOf(address(vault)), 40);
        assertEq(vault.nextLockId(), 4);
        assertEq(vault.getLock(0).unlockTime, 1_001);
        assertFalse(vault.getLock(0).withdrawn);
    }

    function testReentryDuringWithdrawalBlocksAllMutations() public {
        for (uint256 i; i < 3; ++i) {
            vault.lock(address(token), 10, 2_000);
        }
        vm.warp(2_000);
        bytes[3] memory attacks = [
            abi.encodeCall(TimeLock.withdraw, (0)),
            abi.encodeCall(TimeLock.extendLock, (2, 3_000)),
            abi.encodeCall(TimeLock.lock, (address(token), 1, 3_000))
        ];
        for (uint256 i; i < attacks.length; ++i) {
            token.configure(0, address(vault), attacks[i]);
            vm.prank(address(token));
            vault.withdraw(i);
            assertFalse(token.callbackSucceeded());
            assertEq(token.callbackResult(), abi.encodeWithSelector(TimeLock.Reentrancy.selector));
        }
        assertEq(token.callbackCount(), 3);
        assertEq(token.balanceOf(address(token)), 30);
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(vault.totalLocked(), 0);
        assertEq(vault.nextLockId(), 3);
    }
}
