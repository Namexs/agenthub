// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Phase 1 smoke tests: the mock must faithfully reproduce the
/// assumptions AgentGate will rely on in Phase 2 — balanceOf-based ownership
/// and soulbound (non-transferable) behaviour.
contract MockAgentIdTest is Test {
    MockAgentId internal mock;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        mock = new MockAgentId();
    }

    function test_NonHolderHasZeroBalance() public view {
        assertEq(mock.balanceOf(alice), 0);
    }

    function test_MintGrantsOwnership() public {
        uint256 tokenId = mock.mint(alice);
        assertEq(mock.balanceOf(alice), 1);
        assertEq(mock.ownerOf(tokenId), alice);
    }

    function test_TransferIsBlocked_Soulbound() public {
        uint256 tokenId = mock.mint(alice);
        vm.prank(alice);
        vm.expectRevert(MockAgentId.Soulbound.selector);
        mock.transferFrom(alice, bob, tokenId);
        // Ownership unchanged after the failed transfer.
        assertEq(mock.ownerOf(tokenId), alice);
    }

    function test_OnlyOwnerCanMint() public {
        vm.prank(alice);
        vm.expectRevert();
        mock.mint(bob);
    }

    function testFuzz_MintGrantsBalance(address to) public {
        vm.assume(to != address(0));
        mock.mint(to);
        assertEq(mock.balanceOf(to), 1);
    }
}
