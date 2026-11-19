// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {IAgentGate} from "../src/interfaces/IAgentGate.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Fake ERC-721: claims EVERYONE holds an Agent ID.
contract FakeAgentId {
    function balanceOf(address) external pure returns (uint256) {
        return 1;
    }
}

/// @notice Agent ID contract whose balanceOf always reverts.
contract RevertingAgentId {
    function balanceOf(address) external pure returns (uint256) {
        revert("boom");
    }
}

/// @notice Agent ID contract returning malformed data (2 bytes, not a uint256).
contract GarbageAgentId {
    fallback() external {
        assembly {
            mstore(0, 0x1234)
            return(0, 2)
        }
    }
}

/// @notice Agent ID contract that tries to call back into the gate from balanceOf.
/// @dev Deliberately stateless in balanceOf: any SSTORE inside would revert in
/// a static context before the callback is even attempted.
contract ReentrantAgentId {
    AgentGate public immutable gate;

    constructor(AgentGate gate_) {
        gate = gate_;
    }

    function balanceOf(address) external returns (uint256) {
        // Attempt to reenter the gate with a state-changing call. Inside the
        // gate's view call this runs in a static context and must revert.
        try gate.verify() {
        // Should never succeed.
        }
            catch {
            // Expected: the inner call reverts (static context / not a holder).
        }
        return 1;
    }

    /// @dev Accept mock Agent IDs (MockAgentId uses _safeMint).
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract AgentGateTest is Test {
    MockAgentId internal mock;
    AgentGate internal gate;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        mock = new MockAgentId();
        gate = new AgentGate(address(mock), block.chainid);
    }

    // --- Constructor guards ---

    function test_ConstructorRejectsZeroAddress() public {
        vm.expectRevert(IAgentGate.ZeroAddress.selector);
        new AgentGate(address(0), block.chainid);
    }

    function test_ConstructorRejectsAddressWithoutCode() public {
        address eoa = makeAddr("eoa");
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.NoCodeAtAgentId.selector, eoa));
        new AgentGate(eoa, block.chainid);
    }

    function test_ConstructorRejectsZeroChainId() public {
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.InvalidChainId.selector, 0));
        new AgentGate(address(mock), 0);
    }

    function test_ConstructorRejectsWrongChain() public {
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.WrongChain.selector, 56, block.chainid));
        new AgentGate(address(mock), 56);
    }

    function test_ConstructorStoresImmutableConfig() public view {
        assertEq(gate.agentIdContract(), address(mock));
        assertEq(gate.expectedChainId(), block.chainid);
    }

    // --- Happy path ---

    function test_NonHolderIsNotHolder() public view {
        assertFalse(gate.isAgentHolder(alice));
    }

    function test_HolderIsHolder() public {
        mock.mint(alice);
        assertTrue(gate.isAgentHolder(alice));
        assertFalse(gate.isAgentHolder(bob));
    }

    function test_RequireAgentHolderPassesForHolder() public {
        mock.mint(alice);
        // Must not revert.
        gate.requireAgentHolder(alice);
    }

    function test_RequireAgentHolderRevertsForNonHolder() public {
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.NotAgentHolder.selector, alice));
        gate.requireAgentHolder(alice);
    }

    function test_VerifyEmitsEvent() public {
        mock.mint(alice);
        vm.expectEmit(true, false, false, false, address(gate));
        emit IAgentGate.AgentHolderVerified(alice);
        vm.prank(alice);
        gate.verify();
    }

    function test_VerifyRevertsForNonHolder() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.NotAgentHolder.selector, alice));
        gate.verify();
    }

    // --- Fail-closed behaviour ---

    function test_ZeroAccountIsNotHolder() public view {
        assertFalse(gate.isAgentHolder(address(0)));
    }

    function test_WrongChainReturnsFalseAndReverts() public {
        mock.mint(alice);
        assertTrue(gate.isAgentHolder(alice));
        vm.chainId(1);
        assertFalse(gate.isAgentHolder(alice));
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.WrongChain.selector, gate.expectedChainId(), 1));
        gate.requireAgentHolder(alice);
    }

    function test_FakeAgentIdContractIsIgnored() public {
        // The gate only reads its ONE configured address. A fake contract
        // claiming everyone is a holder changes nothing.
        FakeAgentId fake = new FakeAgentId();
        assertEq(fake.balanceOf(alice), 1); // the fake itself lies
        assertFalse(gate.isAgentHolder(alice)); // the gate does not listen to it
    }

    function test_RevertingAgentIdFailsClosed() public {
        RevertingAgentId bad = new RevertingAgentId();
        AgentGate badGate = new AgentGate(address(bad), block.chainid);
        assertFalse(badGate.isAgentHolder(alice));
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.NotAgentHolder.selector, alice));
        badGate.requireAgentHolder(alice);
    }

    function test_GarbageReturnFailsClosed() public {
        GarbageAgentId garbage = new GarbageAgentId();
        AgentGate garbageGate = new AgentGate(address(garbage), block.chainid);
        assertFalse(garbageGate.isAgentHolder(alice));
    }

    function test_ReentrantAgentIdCannotChangeState() public {
        // The evil contract's balanceOf tries to call verify() (state-changing).
        // In production isAgentHolder is invoked via eth_call (STATICCALL), so
        // any state change inside reverts. Simulate that with a staticcall.
        // The evil contract HOLDS a mock Agent ID, so verify() would pass its
        // holder check — only the static context blocks the state change.
        // NOTE: the evil contract still *lies* about holdings (returns 1) —
        // a malicious TRUSTED contract is outside the threat model: the
        // trusted address is immutable and must be the official contract.
        AgentGate placeholder = new AgentGate(address(mock), block.chainid);
        ReentrantAgentId evil = new ReentrantAgentId(placeholder);
        mock.mint(address(evil));
        AgentGate evilGate = new AgentGate(address(evil), block.chainid);

        vm.recordLogs();
        (bool ok, bytes memory ret) =
            address(evilGate).staticcall(abi.encodeWithSelector(AgentGate.isAgentHolder.selector, alice));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(ok, "staticcall should succeed");
        assertTrue(abi.decode(ret, (bool)), "evil balanceOf returns 1");
        assertEq(logs.length, 0, "no event emitted: verify() never executed");
    }

    // --- Differential test: gate must agree with a direct balanceOf read ---

    function testFuzz_GateAgreesWithDirectBalance(address user, bool mintIt) public {
        vm.assume(user != address(0));
        vm.assume(user.code.length == 0); // _safeMint needs an EOA
        if (mintIt) mock.mint(user);
        bool direct = mock.balanceOf(user) > 0;
        assertEq(gate.isAgentHolder(user), direct);
    }
}
