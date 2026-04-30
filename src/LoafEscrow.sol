// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LoafEscrow {
    using SafeERC20 for IERC20;

    enum JobState { OPEN, ACTIVE, IN_REVIEW, COMPLETE, FAILED }

    struct ActorProfile {
        uint256 id;
        address addr;
        string axlPublicKey;
        uint16 workerScore;
        uint16 verifierScore;
        uint16 posterScore;
        uint32 workerJobs;
        uint32 verifierJobs;
        uint32 posterJobs;
        bool exists;
    }

    struct Job {
        uint256 posterId;
        uint256 workerId;
        uint256[] verifierIds;
        string criteria;
        bytes32 outputHash;
        uint256 workerAmount;
        uint256 verifierFeeEach;
        uint8 verifierCount;
        uint8 quorumThreshold;
        uint8 passVotes;
        uint8 failVotes;
        uint16 minVerifierScore;
        uint256 expiresAt;
        JobState state;
    }
}
