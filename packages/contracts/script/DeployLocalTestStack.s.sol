// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {TokenBalanceValidator} from "../src/validators/TokenBalanceValidator.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @notice Deploys a full AGENTHUB stack on a LOCAL anvil chain for the
/// frontend integration test (apps/web/scripts/anvil-integration.mjs).
/// NOT the production deploy path (DeployAgentHub.s.sol): this script
/// deploys directly with admin = deployer, so the test harness can
/// create quests, define badges, and mint Agent IDs without a Safe +
/// timelock. The deploy script itself is covered by DeployScriptTest;
/// this script's subject is the FRONTEND's read/write patterns against
/// a live chain. The deployed wiring (QM as the only score source and
/// badge issuer, gate in front of completions) is identical to
/// production.
///
/// Writes `.anvil-deployment.json` in the contracts package root
/// (gitignored); the wrapper copies it to apps/web/ for the checks.
///
/// Run: forge script script/DeployLocalTestStack.s.sol --rpc-url
/// http://127.0.0.1:8545 --broadcast --private-key <anvil key 0>
contract DeployLocalTestStack is Script {
    // Anvil default accounts (deterministic). The deployer key is the
    // PUBLIC anvil test key 0 — it holds no real funds anywhere and is
    // only ever used against the local anvil instance. It is passed
    // explicitly to startBroadcast: the no-arg form uses forge's default
    // sender, not the --private-key account.
    uint256 internal constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address internal constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant ALICE = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address internal constant BOB = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    uint256 internal constant ALICE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 internal constant VERIFIER_KEY = 0xA11CE5; // same as AttestationTest

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    struct Stack {
        MockAgentId mockId;
        AgentGate gate;
        Reputation reputation;
        Achievement achievement;
        QuestManager qm;
        MockERC20 token;
        TokenBalanceValidator validator;
        uint256 deployBlock;
        uint256 q1;
        uint256 q2;
        uint256 q3;
    }

    function run() external {
        Stack memory s;
        // fromBlock for the frontend's event queries: the block before
        // the first deployment tx (fresh anvil has no AGENTHUB events
        // before this point).
        s.deployBlock = block.number;

        vm.startBroadcast(DEPLOYER_KEY);
        _deploy(s);
        _seed(s);
        vm.stopBroadcast();

        // Alice completes all three quests (the third via a real EIP-712
        // attestation signed by the verifier — the exact flow the
        // frontend's AttestationForm performs).
        vm.startBroadcast(ALICE_KEY);
        _completeAsAlice(s);
        vm.stopBroadcast();

        _writeJson(s);
    }

    function _deploy(Stack memory s) internal {
        address verifier = vm.addr(VERIFIER_KEY);
        s.mockId = new MockAgentId();
        s.gate = new AgentGate(address(s.mockId), block.chainid);
        s.reputation = new Reputation(DEPLOYER);
        s.achievement = new Achievement(DEPLOYER);
        s.qm = new QuestManager(address(s.gate), address(s.reputation), address(s.achievement), DEPLOYER);
        s.token = new MockERC20();
        s.validator = new TokenBalanceValidator(address(s.token), 100);

        // Wiring (identical to production): QM is the only score source
        // and badge issuer; deployer holds creator + badge-manager roles
        // for the test harness (production: creator address + multisig).
        s.reputation.grantRole(s.reputation.SCORE_SOURCE_ROLE(), address(s.qm));
        s.achievement.grantRole(s.achievement.ISSUER_ROLE(), address(s.qm));
        s.achievement.grantRole(s.achievement.BADGE_MANAGER_ROLE(), DEPLOYER);
        s.qm.grantRole(s.qm.QUEST_CREATOR_ROLE(), DEPLOYER);
        s.qm.grantRole(s.qm.VERIFIER_ROLE(), verifier);

        s.qm.approveValidator(address(s.validator), "TokenBalanceValidator", "1.0.0", "docs/token-balance-validator");
        s.achievement.defineBadge(1, "First Steps", "ipfs://badge1");
        s.achievement.defineBadge(2, "Token Holder", "ipfs://badge2");

        s.mockId.mint(ALICE);
        s.mockId.mint(BOB);
        s.token.mint(ALICE, 100); // alice passes the OnChain validator
    }

    function _seed(Stack memory s) internal {
        s.q1 = s.qm
            .createQuest(
                "First Steps",
                "Complete your first quest",
                IQuestManager.QuestType.OneTime,
                IQuestManager.ValidationKind.CheckIn,
                address(0),
                50,
                1,
                block.timestamp,
                block.timestamp + 30 days,
                0,
                1
            );
        s.q2 = s.qm
            .createQuest(
                "Hold 100 Tokens",
                "Hold at least 100 TEST tokens",
                IQuestManager.QuestType.OneTime,
                IQuestManager.ValidationKind.OnChain,
                address(s.validator),
                100,
                2,
                block.timestamp,
                block.timestamp + 30 days,
                0,
                1
            );
        s.q3 = s.qm
            .createQuest(
                "Post on X",
                "Share AGENTHUB on X (attested)",
                IQuestManager.QuestType.OneTime,
                IQuestManager.ValidationKind.Attested,
                address(0),
                100,
                0,
                block.timestamp,
                block.timestamp + 30 days,
                0,
                1
            );
    }

    function _completeAsAlice(Stack memory s) internal {
        s.qm.completeQuest(s.q1);
        s.qm.completeQuest(s.q2);
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _signAttestation(VERIFIER_KEY, address(s.qm), ALICE, s.q3, 0, deadline);
        s.qm.completeQuestWithAttestation(s.q3, deadline, _sigs(sig));
    }

    function _writeJson(Stack memory s) internal {
        // NOTE: the first serialize arg is the OBJECT KEY (a name), not
        // the accumulated JSON — reassigning it (the obvious-looking
        // pattern) creates a new object per call and only the last key
        // survives. Keep the key constant; the last call returns the
        // complete JSON.
        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeUint(obj, "deployBlock", s.deployBlock);
        vm.serializeAddress(obj, "agentId", address(s.mockId));
        vm.serializeAddress(obj, "agentGate", address(s.gate));
        vm.serializeAddress(obj, "questManager", address(s.qm));
        vm.serializeAddress(obj, "reputation", address(s.reputation));
        vm.serializeAddress(obj, "achievement", address(s.achievement));
        vm.serializeAddress(obj, "validator", address(s.validator));
        vm.serializeAddress(obj, "token", address(s.token));
        vm.serializeAddress(obj, "deployer", DEPLOYER);
        vm.serializeAddress(obj, "alice", ALICE);
        vm.serializeAddress(obj, "bob", BOB);
        string memory json = vm.serializeAddress(obj, "verifier", vm.addr(VERIFIER_KEY));
        vm.writeJson(json, ".anvil-deployment.json");
    }

    function _signAttestation(
        uint256 key,
        address qm,
        address account,
        uint256 questId,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("AGENTHUB QuestManager")),
                keccak256(bytes("1")),
                block.chainid,
                qm
            )
        );
        bytes32 structHash =
            keccak256(abi.encode(QuestManager(qm).ATTESTATION_TYPEHASH(), account, questId, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev PHASE 6 (R-010): completeQuestWithAttestation takes a bytes[]
    /// array now; this wraps a single signature (mechanical adapter, no
    /// behavior change).
    function _sigs(bytes memory sig) internal pure returns (bytes[] memory sigs) {
        sigs = new bytes[](1);
        sigs[0] = sig;
    }
}
