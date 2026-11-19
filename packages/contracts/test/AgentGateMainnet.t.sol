// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {IAgentGate} from "../src/interfaces/IAgentGate.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Fake ERC-721: claims EVERYONE holds an Agent ID. Deployed on
/// mainnet by mistake, it would let anyone through the gate — the mainnet
/// lock must reject it at deploy time.
contract FakeNft {
    function balanceOf(address) external pure returns (uint256) {
        return 1;
    }
}

/// @notice TEMUAN 2 regression tests: AgentGate must lock the official
/// Agent ID address on BSC mainnet (56), accept the mock on testnet (97)
/// and local (31337), and reject every other chain.
contract AgentGateMainnetTest is Test {
    MockAgentId internal mock;
    AgentGate internal gate;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    address internal constant OFFICIAL = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function setUp() public {
        mock = new MockAgentId();
        mock.mint(alice);
        gate = new AgentGate(address(mock), block.chainid);
    }

    function test_OfficialAddressConstantMatchesKnownAddress() public view {
        // Pins the constant to the well-known official address. The EIP-55
        // checksum of this literal was verified out-of-band with
        // `cast --to-checksum-address`.
        assertEq(gate.OFFICIAL_AGENT_ID(), OFFICIAL);
        assertEq(gate.OFFICIAL_AGENT_ID(), 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
    }

    function test_MainnetAcceptsOfficialAgentId() public {
        vm.chainId(56);
        // Simulate the official contract: etch the mock's code at the
        // official address. The etched copy has fresh storage, so its
        // Ownable owner is address(0) — mint as address(0) to give alice
        // a balance there. (The real mainnet contract cannot be tested
        // locally; only the gate's addressing logic is under test here.)
        vm.etch(OFFICIAL, address(mock).code);
        vm.prank(address(0));
        MockAgentId(OFFICIAL).mint(alice);

        AgentGate mainnetGate = new AgentGate(OFFICIAL, 56);
        assertEq(mainnetGate.agentIdContract(), OFFICIAL);
        assertEq(mainnetGate.expectedChainId(), 56);
        assertTrue(mainnetGate.isAgentHolder(alice));
        assertFalse(mainnetGate.isAgentHolder(bob));
    }

    function test_MainnetRejectsMockAddress() public {
        vm.chainId(56);
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.UnofficialAgentId.selector, address(mock), 56));
        new AgentGate(address(mock), 56);
    }

    function test_MainnetRejectsFakeNft() public {
        vm.chainId(56);
        FakeNft fake = new FakeNft();
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.UnofficialAgentId.selector, address(fake), 56));
        new AgentGate(address(fake), 56);
    }

    function test_MainnetRejectsArbitraryContract() public {
        vm.chainId(56);
        MockAgentId other = new MockAgentId();
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.UnofficialAgentId.selector, address(other), 56));
        new AgentGate(address(other), 56);
    }

    function test_TestnetAcceptsMock() public {
        vm.chainId(97);
        AgentGate testnetGate = new AgentGate(address(mock), 97);
        assertEq(testnetGate.agentIdContract(), address(mock));
        assertTrue(testnetGate.isAgentHolder(alice));
        assertFalse(testnetGate.isAgentHolder(bob));
    }

    function test_LocalAcceptsMock() public {
        // Default Foundry chainId is 31337 — covered by setUp in the other
        // suites, but asserted explicitly here for the allowlist.
        AgentGate localGate = new AgentGate(address(mock), 31337);
        assertEq(localGate.agentIdContract(), address(mock));
        assertTrue(localGate.isAgentHolder(alice));
    }

    function test_UnsupportedChainReverts() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.UnsupportedChain.selector, 1));
        new AgentGate(address(mock), 1);
    }

    function test_UnsupportedChainRevertsPolygon() public {
        vm.chainId(137);
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.UnsupportedChain.selector, 137));
        new AgentGate(address(mock), 137);
    }

    function test_WrongChainStillCheckedBeforeMainnetLock() public {
        // On chain 31337, asking for a mainnet gate must revert WrongChain
        // (not UnofficialAgentId): the chain check fires first.
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.WrongChain.selector, 56, 31337));
        new AgentGate(address(mock), 56);
    }
}
