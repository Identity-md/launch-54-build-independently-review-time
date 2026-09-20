// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Lock} from "../src/Lock.sol";

contract LockTest is Test {
    Lock internal token;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        token = new Lock();
    }

    function testMetadataAndSupply() public view {
        assertEq(token.name(), "Lock");
        assertEq(token.symbol(), "LOCK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function testTransferAndApprovalEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Lock.Transfer(address(this), alice, 50);
        assertTrue(token.transfer(alice, 50));
        vm.expectEmit(true, true, false, true, address(token));
        emit Lock.Approval(address(this), bob, 100);
        assertTrue(token.approve(bob, 100));
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, 75));
        assertEq(token.allowance(address(this), bob), 25);
        assertEq(token.balanceOf(alice), 125);
    }

    function testAllowanceFailureAndRevocation() public {
        vm.prank(bob);
        vm.expectRevert(Lock.InsufficientAllowance.selector);
        token.transferFrom(address(this), alice, 1);
        token.approve(bob, 10);
        token.approve(bob, 0);
        vm.prank(bob);
        vm.expectRevert(Lock.InsufficientAllowance.selector);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 0);
    }

    function testInfiniteAllowanceAndSelfAndZeroTransfers() public {
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(address(this), alice, 10);
        assertEq(token.allowance(address(this), bob), type(uint256).max);
        vm.prank(alice);
        token.transfer(alice, 10);
        vm.prank(bob);
        token.transfer(alice, 0);
        assertEq(token.balanceOf(alice), 10);
    }

    function testInvalidAddressesAndInsufficientBalance() public {
        vm.expectRevert(Lock.ZeroAddress.selector);
        token.transfer(address(0), 0);
        vm.expectRevert(Lock.ZeroAddress.selector);
        token.approve(address(0), 1);
        vm.expectRevert(Lock.ZeroAddress.selector);
        token.transferFrom(address(0), alice, 0);
        vm.prank(alice);
        vm.expectRevert(Lock.InsufficientBalance.selector);
        token.transfer(bob, 1);
        vm.prank(alice);
        token.approve(bob, 10);
        vm.prank(bob);
        vm.expectRevert(Lock.InsufficientBalance.selector);
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, bob), 10);
    }

    function testNoMintOrAdminSelectors() public {
        bytes[5] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", bob, 1),
            abi.encodeWithSignature("transferOwnership(address)", bob),
            abi.encodeWithSignature("upgradeTo(address)", bob),
            abi.encodeWithSignature("initialize(address)", bob),
            abi.encodeWithSignature("setMinter(address)", bob)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok);
        }
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzzConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, token.totalSupply());
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice) + token.balanceOf(address(this)), token.totalSupply());
        vm.prank(alice);
        token.transfer(address(this), amount);
        assertEq(token.balanceOf(address(this)), token.totalSupply());
    }
}
