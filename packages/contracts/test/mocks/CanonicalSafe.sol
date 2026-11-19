// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockSafeSingleton} from "./MockSafeProxy.sol";

/// @notice Test helper: builds a Safe proxy with GENUINE canonical proxy
/// bytecode (etched) + mock singleton logic etched at the canonical
/// singleton address, initialized through the proxy. The result is
/// indistinguishable from a real Safe for validation purposes: canonical
/// masterCopy, canonical proxy codehash, real setup flow, VERSION
/// answered through the delegatecall.
/// @dev The proxy bytecode constants are the exact runtime code of proxies
/// created by the canonical factories on a BSC testnet fork — see
/// script/ProbeSafeProxy.s.sol. The two versions differ only in the
/// metadata-hash suffix; the executable code is identical.
/// @dev The singleton LOGIC is a mock (the real 23 KB singleton bytecode
/// is not embedded in tests). That is the right scope for these tests:
/// validation checks the singleton ADDRESS + the proxy CODEHASH, not the
/// singleton's bytecode — and the singleton addresses were verified
/// against live BSC 56/97 bytecode separately (see
/// agenthub-final-pretestnet/SAFE_VALIDATION_REVIEW.md).
contract CanonicalSafeHelper is Test {
    address internal constant SAFE_V141 = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address internal constant SAFE_V130 = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;

    bytes internal constant PROXY_CODE_V141 =
        hex"608060405273ffffffffffffffffffffffffffffffffffffffff600054167fa619486e0000000000000000000000000000000000000000000000000000000060003514156050578060005260206000f35b3660008037600080366000845af43d6000803e60008114156070573d6000fd5b3d6000f3fea264697066735822122003d1488ee65e08fa41e58e888a9865554c535f2c77126a82cb4c0f917f31441364736f6c63430007060033";
    bytes internal constant PROXY_CODE_V130 =
        hex"608060405273ffffffffffffffffffffffffffffffffffffffff600054167fa619486e0000000000000000000000000000000000000000000000000000000060003514156050578060005260206000f35b3660008037600080366000845af43d6000803e60008114156070573d6000fd5b3d6000f3fea2646970667358221220d1429297349653a4918076d650332de1a1068c5f3e07c5c82360c277770b955264736f6c63430007060033";

    bytes32 internal constant PROXY_CODEHASH_V141 = 0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c;
    bytes32 internal constant PROXY_CODEHASH_V130 = 0xb89c1b3bdf2cf8827818646bce9a8f6e372885f8c55e5c07acbd307cb133b000;

    uint256 internal _safeNonce;

    /// @notice Deploy a v1.4.1 canonical-bytecode Safe proxy.
    function deployCanonicalSafe(address[] memory owners, uint256 threshold) internal returns (address proxy) {
        return deployCanonicalSafeVersion(owners, threshold, true);
    }

    /// @notice Deploy a canonical-bytecode Safe proxy (v1.4.1 or v1.3.0).
    function deployCanonicalSafeVersion(address[] memory owners, uint256 threshold, bool v141)
        internal
        returns (address proxy)
    {
        return deployCanonicalSafeCustom(owners, threshold, v141, v141 ? "1.4.1" : "1.3.0");
    }

    /// @notice Deploy a canonical-bytecode Safe proxy whose singleton
    /// reports an arbitrary VERSION() string (for the version-mismatch
    /// test — a real singleton never reports a wrong version, so this
    /// can only happen with a tampered singleton).
    function deployCanonicalSafeCustom(address[] memory owners, uint256 threshold, bool v141, string memory version)
        internal
        returns (address proxy)
    {
        address singletonAddr = v141 ? SAFE_V141 : SAFE_V130;
        MockSafeSingleton singletonLogic = new MockSafeSingleton(version);
        vm.etch(singletonAddr, address(singletonLogic).code);
        _safeNonce++;
        proxy = makeAddr(string.concat("canonical-safe-", vm.toString(_safeNonce)));
        vm.etch(proxy, v141 ? PROXY_CODE_V141 : PROXY_CODE_V130);
        vm.store(proxy, bytes32(uint256(0)), bytes32(uint256(uint160(singletonAddr))));
        // Initialize through the proxy: the fallback delegatecalls setup
        // into the etched singleton logic, writing threshold/owners into
        // the PROXY's storage — exactly like a real Safe creation.
        (bool ok,) = proxy.call(
            abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                owners,
                threshold,
                address(0),
                bytes(""),
                address(0),
                address(0),
                uint256(0),
                address(0)
            )
        );
        require(ok, "CanonicalSafeHelper: setup failed");
    }
}
