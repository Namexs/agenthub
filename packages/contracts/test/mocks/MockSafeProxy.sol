// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Safe-singleton stand-in for tests. Its storage layout
/// mirrors the real Safe: slot 0 = singleton address (reads the proxy's
/// masterCopy when delegatecalled), slot 1 = threshold, slot 2 = owners.
/// It is NEVER called directly — only via delegatecall from MockSafeProxy
/// (or from an etched canonical proxy in CanonicalSafeHelper), so its
/// storage lives in the proxy. `setup` matches the real Safe setup
/// signature (8 args) so the same calldata works against both.
contract MockSafeSingleton {
    address public singleton; // slot 0
    uint256 internal _threshold; // slot 1
    address[] internal _owners; // slot 2
    // Immutable strings are not allowed in Solidity, so the version is
    // stored packed in 32 bytes ("1.4.1" / "1.3.0" / "9.9.9" all fit)
    // and unpacked by VERSION(). Immutables live in the CALLEE's code,
    // so they survive delegatecall AND vm.etch of this contract's code.
    bytes32 internal immutable _version;

    constructor(string memory version_) {
        _version = bytes32(bytes(version_));
    }

    function setup(
        address[] calldata owners_,
        uint256 threshold_,
        address, /* to */
        bytes calldata, /* data */
        address, /* fallbackHandler */
        address, /* paymentToken */
        uint256, /* payment */
        address payable /* paymentReceiver */
    ) external {
        _threshold = threshold_;
        _owners = owners_;
    }

    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    function VERSION() external view returns (string memory) {
        bytes32 v = _version;
        uint256 len = 0;
        while (len < 32 && v[len] != bytes1(0)) {
            len++;
        }
        bytes memory out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = v[i];
        }
        return string(out);
    }
}

/// @notice Minimal Safe-proxy stand-in for tests: same SHAPE as the
/// canonical SafeProxy (masterCopy in slot 0, everything else
/// delegatecalled to it). Its runtime bytecode is NOT the canonical proxy
/// bytecode — that is intentional: it serves the explicit (31337) path,
/// where the operator supplies the expected codehash, and the negative
/// codehash test (a proxy-shaped contract without canonical bytecode must
/// be rejected on the canonical path). For a proxy WITH canonical
/// bytecode, see CanonicalSafeHelper (etches the real proxy bytecode).
contract MockSafeProxy {
    address internal _masterCopy; // slot 0

    constructor(address singleton_, address[] memory owners_, uint256 threshold_) {
        _masterCopy = singleton_;
        (bool ok,) = singleton_.delegatecall(
            abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                owners_,
                threshold_,
                address(0),
                bytes(""),
                address(0),
                address(0),
                uint256(0),
                address(0)
            )
        );
        require(ok, "MockSafeProxy: setup failed");
    }

    function masterCopy() external view returns (address) {
        return _masterCopy;
    }

    fallback() external payable {
        address target = _masterCopy;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

/// @notice Spoof Safe: implements the full Safe view interface AND returns
/// a canonical singleton from masterCopy() — but it is a plain contract,
/// not a canonical proxy. It must be REJECTED by the codehash check:
/// this is the test that proves masterCopy() spoofing no longer works.
contract SpoofSafe {
    address[] internal _owners;
    uint256 internal _threshold;
    address internal _fakeSingleton;

    constructor(address[] memory owners_, uint256 threshold_, address fakeSingleton_) {
        _owners = owners_;
        _threshold = threshold_;
        _fakeSingleton = fakeSingleton_;
    }

    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    function masterCopy() external view returns (address) {
        return _fakeSingleton;
    }

    function VERSION() external pure returns (string memory) {
        return "1.4.1";
    }
}
