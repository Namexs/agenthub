// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ValidateSafe} from "../script/ValidateSafe.s.sol";
import {SafeValidation} from "../script/SafeValidation.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockSafe} from "./mocks/MockSafe.sol";
import {MockSafeProxy, MockSafeSingleton, SpoofSafe} from "./mocks/MockSafeProxy.sol";
import {CanonicalSafeHelper} from "./mocks/CanonicalSafe.sol";

/// @notice FINAL REMEDIATION (Phase 1) — tests for the strengthened
/// SafeValidation library (canonical singleton + proxy codehash + VERSION,
/// not just getThreshold/getOwners), exercised through ValidateSafe's
/// parameterized runWith(). The same validation is enforced inside
/// DeployAgentHub.deploy(); ValidateSafe.run() is the thin env-driven
/// wrapper over runWith (its env parsing is forge-std's job; the
/// runWith branch logic is covered here, including the mismatched-values
/// require). No broadcast, no key needed.
/// @dev These tests deliberately use NO vm.setEnv: forge runs tests in
/// parallel threads and setEnv mutates process-global state, so an
/// env-driven test can read a sibling test's values (this flaked 12/16
/// tests in the first version of this file). The DeployScript run()
/// tests still cover the env-driven entry points, with the env sets kept
/// immediately adjacent to the run() call.
contract SafeValidationTest is CanonicalSafeHelper {
    ValidateSafe internal script;

    function setUp() public {
        script = new ValidateSafe();
        vm.chainId(97);
        vm.warp(1_000_000);
    }

    function _owners(uint256 n) internal returns (address[] memory owners) {
        owners = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            owners[i] = makeAddr(string.concat("safe-owner-", vm.toString(i)));
        }
    }

    // --- Canonical path: genuine Safes ---

    function test_ValidateSafeAcceptsGenuineV141() public {
        address safe = deployCanonicalSafe(_owners(3), 2);
        (uint256 threshold, address[] memory owners) = script.runWith(safe, address(0), bytes32(0));
        assertEq(threshold, 2);
        assertEq(owners.length, 3);
    }

    function test_ValidateSafeAcceptsGenuineV130() public {
        address safe = deployCanonicalSafeVersion(_owners(5), 3, false);
        (uint256 threshold, address[] memory owners) = script.runWith(safe, address(0), bytes32(0));
        assertEq(threshold, 3);
        assertEq(owners.length, 5);
    }

    function test_ValidateSafeAcceptsExplicitPathLocal() public {
        vm.chainId(31337);
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        MockSafeProxy proxy = new MockSafeProxy(address(singleton), _owners(3), 2);
        (uint256 threshold, address[] memory owners) =
            script.runWith(address(proxy), address(singleton), address(proxy).codehash);
        assertEq(threshold, 2);
        assertEq(owners.length, 3);
    }

    function test_ValidateSafeRejectsMismatchedExplicitValues() public {
        // Singleton given but codehash missing (and vice versa): the
        // wrapper must refuse rather than silently take a half-specified
        // explicit path.
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        MockSafeProxy proxy = new MockSafeProxy(address(singleton), _owners(3), 2);
        vm.expectRevert("ValidateSafe: set both SAFE_SINGLETON and SAFE_PROXY_CODEHASH");
        script.runWith(address(proxy), address(singleton), bytes32(0));
        vm.expectRevert("ValidateSafe: set both SAFE_SINGLETON and SAFE_PROXY_CODEHASH");
        script.runWith(address(proxy), address(0), address(proxy).codehash);
    }

    // --- Canonical path: rejections ---

    function test_ValidateSafeRejectsEoa() public {
        address eoa = makeAddr("eoa-multisig");
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.NotASafe.selector, eoa, "no code"));
        script.runWith(eoa, address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.NotASafe.selector, address(0), "no code"));
        script.runWith(address(0), address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsNonSafeContract() public {
        MockAgentId notSafe = new MockAgentId();
        vm.expectRevert(
            abi.encodeWithSelector(SafeValidation.NotASafe.selector, address(notSafe), "getThreshold failed")
        );
        script.runWith(address(notSafe), address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsThresholdOne() public {
        MockSafe weak = new MockSafe(_owners(3), 1);
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsafeThreshold.selector, address(weak), 1, 3));
        script.runWith(address(weak), address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsThresholdAboveOwners() public {
        MockSafe broken = new MockSafe(_owners(2), 3);
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsafeThreshold.selector, address(broken), 3, 2));
        script.runWith(address(broken), address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsFakeInterface() public {
        // A contract implementing getThreshold/getOwners but NOT
        // masterCopy: passes the old check, fails the new one.
        MockSafe fake = new MockSafe(_owners(3), 2);
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.NotASafe.selector, address(fake), "masterCopy failed"));
        script.runWith(address(fake), address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsSpoofedMasterCopy() public {
        // The Phase 1 key test: a contract that fakes masterCopy() to
        // return a canonical singleton AND answers VERSION() — but is
        // not a canonical proxy. The codehash check must reject it.
        SpoofSafe spoof = new SpoofSafe(_owners(3), 2, SAFE_V141);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeValidation.UnknownProxyCodehash.selector, address(spoof), address(spoof).codehash
            )
        );
        script.runWith(address(spoof), address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsMockProxyOnCanonicalPath() public {
        // A proxy-SHAPED contract (real masterCopy + delegatecall) whose
        // bytecode is not the canonical proxy bytecode: rejected on the
        // canonical path even though its singleton is canonical.
        MockSafeSingleton singletonLogic = new MockSafeSingleton("1.4.1");
        vm.etch(SAFE_V141, address(singletonLogic).code);
        MockSafeProxy proxy = new MockSafeProxy(SAFE_V141, _owners(3), 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeValidation.UnknownProxyCodehash.selector, address(proxy), address(proxy).codehash
            )
        );
        script.runWith(address(proxy), address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsWrongVersion() public {
        address safe = deployCanonicalSafeCustom(_owners(3), 2, true, "9.9.9");
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.VersionMismatch.selector, safe, "9.9.9"));
        script.runWith(safe, address(0), bytes32(0));
    }

    function test_ValidateSafeRejectsWrongChain() public {
        address safe = deployCanonicalSafe(_owners(3), 2);
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsupportedChain.selector, 1));
        script.runWith(safe, address(0), bytes32(0));
    }

    // --- Explicit path (31337): rejections ---

    function test_ExplicitPathRejectsWrongSingleton() public {
        vm.chainId(31337);
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        MockSafeProxy proxy = new MockSafeProxy(address(singleton), _owners(3), 2);
        vm.expectRevert(
            abi.encodeWithSelector(SafeValidation.UnknownSingleton.selector, address(proxy), address(singleton))
        );
        script.runWith(address(proxy), makeAddr("wrong-singleton"), address(proxy).codehash);
    }

    function test_ExplicitPathRejectsWrongCodehash() public {
        vm.chainId(31337);
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        MockSafeProxy proxy = new MockSafeProxy(address(singleton), _owners(3), 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeValidation.UnknownProxyCodehash.selector, address(proxy), address(proxy).codehash
            )
        );
        script.runWith(
            address(proxy),
            address(singleton),
            bytes32(uint256(0x1111111111111111111111111111111111111111111111111111111111111111))
        );
    }

    function test_ExplicitPathRejectsProductionChain() public {
        // Explicit values on chain 97: the local-only path must refuse.
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        MockSafeProxy proxy = new MockSafeProxy(address(singleton), _owners(3), 2);
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsupportedChain.selector, 97));
        script.runWith(address(proxy), address(singleton), address(proxy).codehash);
    }
}
