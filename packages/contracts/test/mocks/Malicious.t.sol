// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQuestManager} from "../../src/interfaces/IQuestManager.sol";
import {IReputation} from "../../src/interfaces/IReputation.sol";
import {IAchievement} from "../../src/interfaces/IAchievement.sol";

/// @notice Agent ID contract that returns 1 byte of garbage instead of a
/// uint256 — exercises AgentGate's fail-closed malformed-returndata path.
contract GarbageAgentId {
    fallback() external {
        assembly {
            mstore(0, 0x01)
            return(0, 1)
        }
    }
}

/// @notice Agent ID contract whose balanceOf always reverts.
contract RevertingAgentId {
    function balanceOf(address) external pure returns (uint256) {
        revert("boom");
    }
}

/// @notice IReputation implementation whose addPoints always reverts —
/// proves completeQuest is atomic when a downstream call fails.
contract RevertingReputation is IReputation {
    error DownstreamBoom();

    function points(address) external pure returns (uint256) {
        return 0;
    }

    function level(address) external pure returns (uint8) {
        return 1;
    }

    function levelThreshold(uint8) external pure returns (uint256) {
        return 0;
    }

    function addPoints(address, uint256, uint256) external pure {
        revert DownstreamBoom();
    }

    function totalEvents(address) external pure returns (uint256) {
        return 0;
    }
}

/// @notice ERC-721 receiver that tries to reenter the Achievement issuer and
/// the QuestManager from inside onERC721Received. With _mint (no callback)
/// the callback must NEVER fire: callbackCount must stay 0.
contract ReentrantReceiver {
    uint256 public callbackCount;
    IAchievement public achievement;
    IQuestManager public qm;
    uint256 public questId;
    uint256 public badgeId;

    constructor(address achievement_, address qm_, uint256 questId_, uint256 badgeId_) {
        achievement = IAchievement(achievement_);
        qm = IQuestManager(qm_);
        questId = questId_;
        badgeId = badgeId_;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        returns (bytes4)
    {
        callbackCount++;
        // Attempt 1: reenter badge issuance.
        try achievement.issue(address(this), badgeId) {} catch {}
        // Attempt 2: reenter quest completion.
        try qm.completeQuest(questId) {} catch {}
        return this.onERC721Received.selector;
    }
}

/// @notice An Agent ID holder contract that tries to exploit the mint
/// callback: during MockAgentId._safeMint it attempts a quest completion
/// from inside onERC721Received, and its fallback tries reentry too.
/// Even this exotic path must award at most ONE completion.
contract MaliciousHolder {
    uint256 public callbackCount;
    IQuestManager public qm;
    uint256 public questId;

    constructor(address qm_, uint256 questId_) {
        qm = IQuestManager(qm_);
        questId = questId_;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        returns (bytes4)
    {
        callbackCount++;
        // Attempt completion from inside the mint callback.
        try qm.completeQuest(questId) {} catch {}
        return this.onERC721Received.selector;
    }

    /// @notice Direct completion attempt (called after mint).
    function attack() external {
        qm.completeQuest(questId);
    }

    /// @notice Fallback reentry attempt — completeQuest never calls
    /// msg.sender, so this must never fire during a completion.
    fallback() external {
        try qm.completeQuest(questId) {} catch {}
    }
}
