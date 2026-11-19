// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ValidateSafe} from "../script/ValidateSafe.s.sol";
import {SafeValidation} from "../script/SafeValidation.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockSafe} from "./mocks/MockSafe.sol";

/// @notice PRE-TESTNET CLEANUP (item 5) — tests for the standalone
/// ValidateSafe pre-deploy script. The same validation is enforced inside
/// DeployAgentHub.deploy(); this script is the early human-readable check
/// operators run before deploying. No broadcast, no key needed.
/// @dev Each test sets ADMIN_MULTISIG explicitly: vm.setEnv persists
/// across tests in one forge run (see REGRESSION_RESULTS §4.2), so no
/// test may rely on another test's env value.
contract SafeValidationTest is Test {
    ValidateSafe internal script;

    function setUp() public {
        script = new ValidateSafe();
        vm.warp(1_000_000);
    }

    function _owners(uint256 n) internal returns (address[] memory owners) {
        owners = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            owners[i] = makeAddr(string.concat("safe-owner-", vm.toString(i)));
        }
    }

    function test_ValidateSafeAcceptsTwoOfThree() public {
        MockSafe safe = new MockSafe(_owners(3), 2);
        vm.setEnv("ADMIN_MULTISIG", vm.toString(address(safe)));
        (uint256 threshold, address[] memory owners) = script.run();
        assertEq(threshold, 2);
        assertEq(owners.length, 3);
    }

    function test_ValidateSafeAcceptsThreeOfFive() public {
        MockSafe safe = new MockSafe(_owners(5), 3);
        vm.setEnv("ADMIN_MULTISIG", vm.toString(address(safe)));
        (uint256 threshold, address[] memory owners) = script.run();
        assertEq(threshold, 3);
        assertEq(owners.length, 5);
    }

    function test_ValidateSafeRejectsEoa() public {
        address eoa = makeAddr("eoa-multisig");
        vm.setEnv("ADMIN_MULTISIG", vm.toString(eoa));
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.NotASafe.selector, eoa, "no code"));
        script.run();
    }

    function test_ValidateSafeRejectsNonSafeContract() public {
        MockAgentId notSafe = new MockAgentId();
        vm.setEnv("ADMIN_MULTISIG", vm.toString(address(notSafe)));
        vm.expectRevert(
            abi.encodeWithSelector(SafeValidation.NotASafe.selector, address(notSafe), "getThreshold failed")
        );
        script.run();
    }

    function test_ValidateSafeRejectsThresholdOne() public {
        MockSafe weak = new MockSafe(_owners(3), 1);
        vm.setEnv("ADMIN_MULTISIG", vm.toString(address(weak)));
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsafeThreshold.selector, address(weak), 1, 3));
        script.run();
    }

    function test_ValidateSafeRejectsThresholdAboveOwners() public {
        MockSafe broken = new MockSafe(_owners(2), 3);
        vm.setEnv("ADMIN_MULTISIG", vm.toString(address(broken)));
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsafeThreshold.selector, address(broken), 3, 2));
        script.run();
    }
}
