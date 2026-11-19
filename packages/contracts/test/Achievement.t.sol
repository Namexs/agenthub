// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Achievement} from "../src/Achievement.sol";
import {IAchievement} from "../src/interfaces/IAchievement.sol";

contract AchievementTest is Test {
    Achievement internal achievement;
    address internal admin = makeAddr("admin");
    address internal issuer = makeAddr("issuer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant BADGE_ID = 1;

    function setUp() public {
        achievement = new Achievement(admin);
        bytes32 issuerRole = achievement.ISSUER_ROLE(); // hoist before prank
        vm.prank(admin);
        achievement.grantRole(issuerRole, issuer);
        vm.prank(admin);
        achievement.defineBadge(BADGE_ID, "First Quest", "ipfs://badge1");
    }

    function test_DefineBadgeStoresMetadata() public view {
        assertTrue(achievement.isBadgeDefined(BADGE_ID));
        assertFalse(achievement.isBadgeDefined(999));
    }

    function test_DefineBadgeRequiresManagerRole() public {
        bytes32 role = achievement.BADGE_MANAGER_ROLE();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role
            )
        );
        achievement.defineBadge(2, "X", "ipfs://x");
    }

    function test_DefineBadgeRejectsZeroId() public {
        vm.prank(admin);
        vm.expectRevert(IAchievement.InvalidBadgeId.selector);
        achievement.defineBadge(0, "X", "ipfs://x");
    }

    function test_DefineBadgeRejectsDuplicate() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAchievement.BadgeAlreadyDefined.selector, BADGE_ID)
        );
        achievement.defineBadge(BADGE_ID, "Again", "ipfs://again");
    }

    function test_DefineBadgeRejectsEmptyName() public {
        vm.prank(admin);
        vm.expectRevert(IAchievement.InvalidBadgeMetadata.selector);
        achievement.defineBadge(2, "", "ipfs://x");
    }

    function test_IssueMintsSoulboundToken() public {
        vm.prank(issuer);
        uint256 tokenId = achievement.issue(alice, BADGE_ID);
        assertEq(tokenId, 1);
        assertEq(achievement.ownerOf(tokenId), alice);
        assertEq(achievement.balanceOf(alice), 1);
        assertTrue(achievement.hasBadge(alice, BADGE_ID));
        assertEq(achievement.badgeOf(tokenId), BADGE_ID);
        assertEq(achievement.tokenURI(tokenId), "ipfs://badge1");
    }

    function test_IssueEmitsEvent() public {
        vm.expectEmit(true, true, true, false, address(achievement));
        emit IAchievement.BadgeIssued(alice, BADGE_ID, 1);
        vm.prank(issuer);
        achievement.issue(alice, BADGE_ID);
    }

    function test_IssueRequiresIssuerRole() public {
        bytes32 role = achievement.ISSUER_ROLE();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role
            )
        );
        achievement.issue(alice, BADGE_ID);
        // Even the admin cannot issue directly — only the QuestManager role.
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, role
            )
        );
        achievement.issue(alice, BADGE_ID);
    }

    function test_IssueRejectsUndefinedBadge() public {
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(IAchievement.BadgeNotDefined.selector, 999));
        achievement.issue(alice, 999);
    }

    function test_IssueRejectsZeroAccount() public {
        vm.prank(issuer);
        vm.expectRevert(IAchievement.ZeroAddress.selector);
        achievement.issue(address(0), BADGE_ID);
    }

    function test_IssueRejectsDuplicateBadge() public {
        vm.prank(issuer);
        achievement.issue(alice, BADGE_ID);
        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(IAchievement.AlreadyHasBadge.selector, alice, BADGE_ID)
        );
        achievement.issue(alice, BADGE_ID);
        assertEq(achievement.balanceOf(alice), 1);
    }

    function test_IssueToNonReceiverContractSucceeds() public {
        // _mint (not _safeMint): no receiver callback, so issuance to a
        // contract without onERC721Received still succeeds. Ownership is
        // verifiable via ownerOf regardless.
        address noReceiver = address(new NoReceiver());
        vm.prank(issuer);
        uint256 tokenId = achievement.issue(noReceiver, BADGE_ID);
        assertEq(achievement.ownerOf(tokenId), noReceiver);
    }

    function test_TransferRevertsSoulbound() public {
        vm.prank(issuer);
        uint256 tokenId = achievement.issue(alice, BADGE_ID);
        vm.prank(alice);
        vm.expectRevert(IAchievement.Soulbound.selector);
        achievement.transferFrom(alice, bob, tokenId);
        vm.prank(alice);
        vm.expectRevert(IAchievement.Soulbound.selector);
        achievement.safeTransferFrom(alice, bob, tokenId);
        assertEq(achievement.ownerOf(tokenId), alice);
    }

    function test_ApproveRevertsSoulbound() public {
        vm.prank(issuer);
        uint256 tokenId = achievement.issue(alice, BADGE_ID);
        vm.prank(alice);
        vm.expectRevert(IAchievement.Soulbound.selector);
        achievement.approve(bob, tokenId);
        vm.prank(alice);
        vm.expectRevert(IAchievement.Soulbound.selector);
        achievement.setApprovalForAll(bob, true);
        assertEq(achievement.getApproved(tokenId), address(0));
        assertFalse(achievement.isApprovedForAll(alice, bob));
    }

    function test_BadgeOfRevertsForNonexistentToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 999)
        );
        achievement.badgeOf(999);
    }

    function test_TokenURIRevertsForNonexistentToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 999)
        );
        achievement.tokenURI(999);
    }

    function test_PauseBlocksIssueButNotReads() public {
        vm.prank(admin);
        achievement.pause();
        vm.prank(issuer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        achievement.issue(alice, BADGE_ID);
        assertFalse(achievement.hasBadge(alice, BADGE_ID));
        vm.prank(admin);
        achievement.unpause();
        vm.prank(issuer);
        achievement.issue(alice, BADGE_ID);
        assertTrue(achievement.hasBadge(alice, BADGE_ID));
    }

    function test_ConstructorRejectsZeroAdmin() public {
        vm.expectRevert(IAchievement.ZeroAddress.selector);
        new Achievement(address(0));
    }

    function testFuzz_IssueGrantsUniqueTokenIds(uint8 n) public {
        // Each issuance mints a distinct token id; badges are per-account.
        vm.assume(n > 0 && n <= 10);
        for (uint256 i = 0; i < n; i++) {
            address user = address(uint160(0x1000 + i));
            vm.prank(admin);
            achievement.defineBadge(100 + i, "Badge", "ipfs://b");
            vm.prank(issuer);
            uint256 tokenId = achievement.issue(user, 100 + i);
            assertEq(tokenId, i + 1);
            assertEq(achievement.badgeOf(tokenId), 100 + i);
        }
    }
}

/// @notice A contract with no ERC-721 receiver function.
contract NoReceiver {}
