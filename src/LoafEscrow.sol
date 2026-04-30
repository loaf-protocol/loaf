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

    // ── Constants ────────────────────────────────────────────────────────────

    IERC20 public immutable usdc;

    uint16 public constant INITIAL_SCORE = 250;
    uint16 public constant MAX_SCORE = 500;

    // Worker rep deltas
    int16 private constant WORKER_PASS_DELTA = 20;
    int16 private constant WORKER_FAIL_DELTA = -30;

    // Verifier rep deltas
    int16 private constant VERIFIER_MAJORITY_DELTA = 10;
    int16 private constant VERIFIER_MINORITY_DELTA = -20;

    // Poster rep deltas
    int16 private constant POSTER_RESOLVE_DELTA = 10;
    int16 private constant POSTER_EXPIRE_DELTA = -15;

    // ── Profile storage ───────────────────────────────────────────────────────

    uint256 public actorCount;
    mapping(uint256 => ActorProfile) private profiles;
    mapping(address => uint256) private addressToProfileId;

    // ── Job storage ───────────────────────────────────────────────────────────

    uint256 public jobCount;
    mapping(uint256 => Job) private jobs;

    // Per-state job arrays for O(1) listing
    mapping(JobState => uint256[]) private jobsByState;
    mapping(uint256 => uint256) private jobStateIndex;

    // Pending verifier applications per job
    mapping(uint256 => uint256[]) private pendingVerifiers;
    mapping(uint256 => mapping(uint256 => bool)) private isPendingVerifier;

    // Verifier assignment tracking
    mapping(uint256 => mapping(uint256 => bool)) private isAssignedVerifier;

    // Vote tracking
    mapping(uint256 => mapping(uint256 => bool)) private hasVoted;

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }
}
