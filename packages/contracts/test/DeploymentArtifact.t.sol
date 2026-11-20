// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployAgentHub} from "../script/DeployAgentHub.s.sol";
import {RecordDeployment} from "../script/RecordDeployment.s.sol";
import {MockSafeProxy, MockSafeSingleton} from "./mocks/MockSafeProxy.sol";

/// @notice PHASE 9.1 (PH7-L18): the deployment artifact is written
/// automatically by the deploy flow, is complete and well-formed, and
/// contains no secrets; RecordDeployment fills the tx hashes from
/// forge's broadcast artifact. Local chain only — no network is
/// touched, and nothing is broadcast.
contract DeploymentArtifactTest is Test {
    DeployAgentHub internal script;
    RecordDeployment internal recorder;

    // Direct deploy() calls originate from the script contract,
    // so the script IS the deployer in these tests.
    address internal deployer;
    address internal multisig;
    address internal creator;
    address internal safeSingleton;
    bytes32 internal safeProxyCodehash;
    address internal pauser = makeAddr("pauser");
    address internal verifier = makeAddr("verifier");

    // NOTE: forge runs tests in parallel, so every test writes to its
    // OWN artifact + fixture paths — a shared path would race (one
    // test's removeFile deleting another's fixture mid-run).
    string internal constant ARTIFACT_FIELDS = "deployments/31337-fields.json";
    string internal constant ARTIFACT_RECORD = "deployments/31337-record.json";
    string internal constant FIXTURE_RECORD = "deployments/broadcast-record.fixture.json";
    string internal constant ARTIFACT_PRESERVE = "deployments/31337-preserve.json";
    string internal constant FIXTURE_PRESERVE = "deployments/broadcast-preserve.fixture.json";
    string internal constant ARTIFACT_MISSING = "deployments/31337-missing.json";

    // Distinct fake tx hashes for the fabricated broadcast file.
    string internal constant HASH_MOCK =
        "0x1111111111111111111111111111111111111111111111111111111111111111";
    string internal constant HASH_GATE =
        "0x2222222222222222222222222222222222222222222222222222222222222222";
    string internal constant HASH_TIMELOCK =
        "0x3333333333333333333333333333333333333333333333333333333333333333";
    string internal constant HASH_REPUTATION =
        "0x4444444444444444444444444444444444444444444444444444444444444444";
    string internal constant HASH_ACHIEVEMENT =
        "0x5555555555555555555555555555555555555555555555555555555555555555";
    string internal constant HASH_QM =
        "0x6666666666666666666666666666666666666666666666666666666666666666";

    function setUp() public {
        script = new DeployAgentHub();
        recorder = new RecordDeployment();
        deployer = address(script);
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("safe-owner-1");
        owners[1] = makeAddr("safe-owner-2");
        owners[2] = makeAddr("safe-owner-3");
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        multisig = address(new MockSafeProxy(address(singleton), owners, 2));
        safeSingleton = address(singleton);
        safeProxyCodehash = multisig.codehash;
        address[] memory creatorOwners = new address[](3);
        creatorOwners[0] = makeAddr("creator-owner-1");
        creatorOwners[1] = makeAddr("creator-owner-2");
        creatorOwners[2] = makeAddr("creator-owner-3");
        creator = address(new MockSafeProxy(address(singleton), creatorOwners, 2));
        vm.warp(1_000_000);
    }

    function _params() internal view returns (DeployAgentHub.DeployParams memory) {
        return DeployAgentHub.DeployParams({
            agentId: address(0), // deploy a mock
            adminMultisig: multisig,
            questCreator: creator,
            pauser: pauser,
            verifier: verifier,
            safeSingleton: safeSingleton,
            safeProxyCodehash: safeProxyCodehash
        });
    }

    function test_ArtifactHasAllRequiredFields() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        // The default path is deployments/<chainId>.json.
        assertEq(script.artifactPath(), "deployments/31337.json", "wrong default artifact path");
        script.writeDeploymentArtifact(d, deployer, ARTIFACT_FIELDS);

        string memory json = vm.readFile(ARTIFACT_FIELDS);
        // Metadata: chain id, block number, timestamp, deployer.
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "wrong chainId");
        assertEq(vm.parseJsonUint(json, ".blockNumber"), block.number, "wrong blockNumber");
        assertEq(vm.parseJsonUint(json, ".timestamp"), block.timestamp, "wrong timestamp");
        assertEq(vm.parseJsonAddress(json, ".deployer"), deployer, "wrong deployer");
        // All six deployed addresses, each a real contract.
        assertEq(vm.parseJsonAddress(json, ".mockAgentId"), d.mockAgentId, "wrong mockAgentId");
        assertEq(vm.parseJsonAddress(json, ".agentGate"), d.agentGate, "wrong agentGate");
        assertEq(vm.parseJsonAddress(json, ".timelock"), d.timelock, "wrong timelock");
        assertEq(vm.parseJsonAddress(json, ".reputation"), d.reputation, "wrong reputation");
        assertEq(vm.parseJsonAddress(json, ".achievement"), d.achievement, "wrong achievement");
        assertEq(vm.parseJsonAddress(json, ".questManager"), d.questManager, "wrong questManager");
        assertTrue(d.mockAgentId.code.length > 0, "mockAgentId has no code");
        assertTrue(d.agentGate.code.length > 0, "agentGate has no code");
        assertTrue(d.timelock.code.length > 0, "timelock has no code");
        assertTrue(d.reputation.code.length > 0, "reputation has no code");
        assertTrue(d.achievement.code.length > 0, "achievement has no code");
        assertTrue(d.questManager.code.length > 0, "questManager has no code");
        // Tx hashes are present but empty until RecordDeployment runs
        // (forge only knows the real hashes after the broadcast).
        assertEq(vm.parseJsonString(json, ".mockAgentIdTxHash"), "", "mock hash not empty");
        assertEq(vm.parseJsonString(json, ".agentGateTxHash"), "", "gate hash not empty");
        assertEq(vm.parseJsonString(json, ".timelockTxHash"), "", "timelock hash not empty");
        assertEq(vm.parseJsonString(json, ".reputationTxHash"), "", "reputation hash not empty");
        assertEq(vm.parseJsonString(json, ".achievementTxHash"), "", "achievement hash not empty");
        assertEq(vm.parseJsonString(json, ".questManagerTxHash"), "", "qm hash not empty");
        // Exact key set: 16 fields, nothing more — no secret fields,
        // no private key, no mnemonic.
        string[] memory keys = vm.parseJsonKeys(json, ".");
        assertEq(keys.length, 16, "artifact does not have exactly 16 fields");
        vm.removeFile(ARTIFACT_FIELDS);
    }

    function test_RecordFillsTxHashesFromBroadcast() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        script.writeDeploymentArtifact(d, deployer, ARTIFACT_RECORD);
        // Fabricate a forge 1.9 broadcast artifact: one CREATE receipt
        // per deployed contract in the top-level `receipts` array,
        // plus a non-create receipt (null contractAddress) that must
        // be ignored.
        vm.writeFile(FIXTURE_RECORD, _broadcastFixture(d));
        string memory path = recorder.record(ARTIFACT_RECORD, FIXTURE_RECORD);
        assertEq(path, ARTIFACT_RECORD, "record returned the wrong path");

        string memory json = vm.readFile(ARTIFACT_RECORD);
        assertEq(vm.parseJsonString(json, ".mockAgentIdTxHash"), HASH_MOCK, "mock hash not filled");
        assertEq(vm.parseJsonString(json, ".agentGateTxHash"), HASH_GATE, "gate hash not filled");
        assertEq(vm.parseJsonString(json, ".timelockTxHash"), HASH_TIMELOCK, "timelock hash not filled");
        assertEq(vm.parseJsonString(json, ".reputationTxHash"), HASH_REPUTATION, "reputation hash not filled");
        assertEq(vm.parseJsonString(json, ".achievementTxHash"), HASH_ACHIEVEMENT, "achievement hash not filled");
        assertEq(vm.parseJsonString(json, ".questManagerTxHash"), HASH_QM, "qm hash not filled");
        // Metadata + addresses preserved verbatim by the rewrite —
        // except blockNumber, which the receipts correct to the block
        // the txs actually landed in (fixture: 0x2a = 42).
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "chainId changed");
        assertEq(vm.parseJsonUint(json, ".blockNumber"), 42, "blockNumber not corrected to mined block");
        assertEq(vm.parseJsonAddress(json, ".deployer"), deployer, "deployer changed");
        assertEq(vm.parseJsonAddress(json, ".questManager"), d.questManager, "qm address changed");
        string[] memory keys = vm.parseJsonKeys(json, ".");
        assertEq(keys.length, 16, "enriched artifact does not have exactly 16 fields");
        vm.removeFile(FIXTURE_RECORD);
        vm.removeFile(ARTIFACT_RECORD);
    }

    function test_RecordPreservesHashesWhenNoMatch() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        script.writeDeploymentArtifact(d, deployer, ARTIFACT_PRESERVE);
        vm.writeFile(FIXTURE_PRESERVE, _broadcastFixture(d));
        recorder.record(ARTIFACT_PRESERVE, FIXTURE_PRESERVE);
        assertEq(
            vm.parseJsonString(vm.readFile(ARTIFACT_PRESERVE), ".questManagerTxHash"),
            HASH_QM,
            "setup: hash not filled"
        );
        // Second run against a dry-run broadcast file (empty receipts
        // array, predicted hashes only): the recorded hashes survive
        // — re-running never clobbers them.
        vm.writeFile(
            FIXTURE_PRESERVE,
            '{"transactions":[{"hash":"0x9999999999999999999999999999999999999999999999999999999999999999","receipt":null}],"receipts":[]}'
        );
        recorder.record(ARTIFACT_PRESERVE, FIXTURE_PRESERVE);
        string memory json = vm.readFile(ARTIFACT_PRESERVE);
        assertEq(vm.parseJsonString(json, ".mockAgentIdTxHash"), HASH_MOCK, "mock hash clobbered");
        assertEq(vm.parseJsonString(json, ".questManagerTxHash"), HASH_QM, "qm hash clobbered");
        assertEq(vm.parseJsonUint(json, ".blockNumber"), 42, "blockNumber clobbered");
        vm.removeFile(FIXTURE_PRESERVE);
        vm.removeFile(ARTIFACT_PRESERVE);
    }

    function test_RecordRevertsWhenBroadcastMissing() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        script.writeDeploymentArtifact(d, deployer, ARTIFACT_MISSING);
        vm.expectRevert(
            abi.encodeWithSelector(RecordDeployment.BroadcastArtifactNotFound.selector, "deployments/nope.json")
        );
        recorder.record(ARTIFACT_MISSING, "deployments/nope.json");
    }

    function test_RecordRevertsWhenDeploymentMissing() public {
        vm.expectRevert(
            abi.encodeWithSelector(RecordDeployment.DeploymentArtifactNotFound.selector, "deployments/99999.json")
        );
        recorder.record("deployments/99999.json", FIXTURE_RECORD);
    }

    /// @notice Builds a broadcast-shaped JSON fixture (forge 1.9's
    /// broadcast/<script>/<chainId>/run-latest.json layout): txs carry
    /// a null per-tx `receipt`, and the top-level `receipts` array
    /// holds one CREATE receipt per deployed contract plus one
    /// non-create receipt (null contractAddress) that must be ignored.
    function _broadcastFixture(DeployAgentHub.Deployment memory d) internal returns (string memory) {
        return string.concat(
            '{"transactions":[',
            _dryTx(HASH_MOCK),
            ",",
            _dryTx(HASH_GATE),
            ",",
            _dryTx(HASH_TIMELOCK),
            ",",
            _dryTx(HASH_REPUTATION),
            ",",
            _dryTx(HASH_ACHIEVEMENT),
            ",",
            _dryTx(HASH_QM),
            '],"receipts":[',
            _receipt(HASH_MOCK, d.mockAgentId),
            ",",
            _receipt(HASH_GATE, d.agentGate),
            ",",
            _receipt(HASH_TIMELOCK, d.timelock),
            ",",
            _receipt(HASH_REPUTATION, d.reputation),
            ",",
            _receipt(HASH_ACHIEVEMENT, d.achievement),
            ",",
            _receipt(HASH_QM, d.questManager),
            ",",
            '{"transactionHash":"0x7777777777777777777777777777777777777777777777777777777777777777",',
            '"contractAddress":null,"blockNumber":"0x2a","status":"0x1"}',
            "]}"
        );
    }

    /// @dev A forge 1.9 broadcast tx entry: the per-tx `receipt` is
    /// always null (receipts live in the top-level array).
    function _dryTx(string memory hash) internal pure returns (string memory) {
        return string.concat('{"hash":"', hash, '","receipt":null}');
    }

    function _receipt(string memory hash, address created) internal returns (string memory) {
        return string.concat(
            '{"transactionHash":"',
            hash,
            '","contractAddress":"',
            vm.toString(created),
            '","blockNumber":"0x2a","status":"0x1"}'
        );
    }
}
