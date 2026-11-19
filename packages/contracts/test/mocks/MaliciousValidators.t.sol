// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQuestValidator} from "../../src/interfaces/IQuestValidator.sol";
import {IQuestManager} from "../../src/interfaces/IQuestManager.sol";

/// @notice Validator whose validate() always reverts — completion must
/// fail closed (whole transaction reverts, no partial state).
contract RevertingValidator is IQuestValidator {
    error ValidatorBoom();

    function validate(address, uint256) external pure returns (bool) {
        revert ValidatorBoom();
    }
}

/// @notice Validator returning 1 byte of garbage instead of a bool — the
/// ABI decode in QuestManager must revert (fail-closed), not misread it.
contract GarbageValidator {
    fallback() external {
        assembly {
            mstore(0, 0x01)
            return(0, 1)
        }
    }
}

/// @notice Validator that tries to reenter completeQuest from inside
/// validate(). Deliberately does NOT declare `is IQuestValidator`: a real
/// attacker is not bound by the interface's view annotation — the function
/// selector still matches, so QuestManager calls it the same way. This is
/// the honest attack: `view` is a compiler annotation, NOT an on-chain
/// enforcement. Only nonReentrant + checks-effects-interactions protect
/// the completion (see QUEST_VALIDATION_DESIGN.md).
contract ReentrantValidator {
    IQuestManager public immutable qm;
    uint256 public questId;

    constructor(address qm_) {
        qm = IQuestManager(qm_);
    }

    function setQuest(uint256 questId_) external {
        questId = questId_;
    }

    function validate(address, uint256) external returns (bool) {
        // Real reentry attempt: must be blocked by nonReentrant.
        try qm.completeQuest(questId) {} catch {}
        return true;
    }
}

/// @notice Rubber-stamp validator: always returns true. Documents the
/// creator-trust caveat — a quest using it behaves exactly like a CheckIn
/// quest. QUEST_CREATOR_ROLE is trusted to pick honest validators.
contract AlwaysTrueValidator is IQuestValidator {
    function validate(address, uint256) external pure returns (bool) {
        return true;
    }
}

/// @notice Validator that WRITES state inside validate() — the attack the
/// interface's `view` annotation cannot stop on its own. Under a regular
/// CALL this would succeed (and could, e.g., flip its own approval flag
/// or reenter); under QuestManager's STATICCALL (Phase 5) the storage
/// write reverts the whole validate() call and the completion fails
/// closed with ValidatorCallFailed.
contract StateChangingValidator {
    uint256 public counter;

    function validate(address, uint256) external returns (bool) {
        counter += 1; // SSTORE inside a staticcall frame: must revert.
        return true;
    }
}

/// @notice Validator returning a 32-byte word with value 2 — the right
/// length, but not a valid bool. abi.decode(bool) would revert with a
/// panic; QuestManager's explicit word check (Phase 5) reverts with
/// InvalidValidatorReturndata instead.
contract InvalidBoolValidator {
    fallback() external {
        assembly {
            mstore(0, 0x02)
            return(0, 32)
        }
    }
}
