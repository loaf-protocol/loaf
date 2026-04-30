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

    // ── Errors ────────────────────────────────────────────────────────────────

    error NotRegistered();
    error AlreadyRegistered();
    error ProfileNotFound();
    error NotPoster();
    error NotWorker();
    error NotAssignedVerifier();
    error AlreadyVoted();
    error AlreadyApplied();
    error VerifierSlotsFull();
    error InvalidState(JobState current);
    error JobExpired();
    error InvalidVerifierCount();
    error InvalidQuorum();
    error ZeroAmount();
    error ZeroHash();
    error BelowMinReputation();

    // ── Events ────────────────────────────────────────────────────────────────

    event ProfileRegistered(uint256 indexed profileId, address indexed addr);
    event AxlKeyUpdated(uint256 indexed profileId, string newKey);
    event ReputationUpdated(uint256 indexed profileId, string role, uint16 newScore);

    event JobPosted(uint256 indexed jobId, uint256 indexed posterId, uint256 workerAmount, uint256 verifierFeeEach, uint8 verifierCount);
    event BidAccepted(uint256 indexed jobId, uint256 indexed workerId);
    event WorkSubmitted(uint256 indexed jobId, bytes32 outputHash);
    event VerifierApplied(uint256 indexed jobId, uint256 indexed verifierProfileId);
    event VerifierAccepted(uint256 indexed jobId, uint256 indexed verifierProfileId);
    event VerdictSubmitted(uint256 indexed jobId, uint256 indexed verifierProfileId, bool pass);

    event JobCompleted(uint256 indexed jobId, uint256 indexed workerId, uint256 amount);
    event JobFailed(uint256 indexed jobId, uint256 indexed posterId, uint256 refund);
    event VerifierFeePaid(uint256 indexed jobId, uint256 indexed verifierProfileId, address verifierAddr, uint256 fee);

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    // ── Profile functions ─────────────────────────────────────────────────────

    function registerProfile(string calldata axlPublicKey) external returns (uint256 profileId) {
        if (addressToProfileId[msg.sender] != 0) revert AlreadyRegistered();
        if (bytes(axlPublicKey).length == 0) revert ZeroHash();

        profileId = ++actorCount;
        profiles[profileId] = ActorProfile({
            id: profileId,
            addr: msg.sender,
            axlPublicKey: axlPublicKey,
            workerScore: INITIAL_SCORE,
            verifierScore: INITIAL_SCORE,
            posterScore: INITIAL_SCORE,
            workerJobs: 0,
            verifierJobs: 0,
            posterJobs: 0,
            exists: true
        });
        addressToProfileId[msg.sender] = profileId;

        emit ProfileRegistered(profileId, msg.sender);
    }

    // ── Job functions ─────────────────────────────────────────────────────────

    function postJob(
        string calldata criteria,
        uint256 workerAmount,
        uint256 verifierFeeEach,
        uint8 verifierCount,
        uint8 quorumThreshold,
        uint16 minVerifierScore,
        uint256 expiresAt
    ) external returns (uint256 jobId) {
        uint256 posterId = _profileIdOf(msg.sender);
        if (workerAmount == 0) revert ZeroAmount();
        if (verifierCount < 1 || verifierCount > 10) revert InvalidVerifierCount();
        if (quorumThreshold < 1 || quorumThreshold > verifierCount) revert InvalidQuorum();
        if (expiresAt <= block.timestamp) revert JobExpired();

        uint256 totalLock = workerAmount + (verifierFeeEach * verifierCount);
        usdc.safeTransferFrom(msg.sender, address(this), totalLock);

        jobId = ++jobCount;
        Job storage j = jobs[jobId];
        j.posterId = posterId;
        j.criteria = criteria;
        j.workerAmount = workerAmount;
        j.verifierFeeEach = verifierFeeEach;
        j.verifierCount = verifierCount;
        j.quorumThreshold = quorumThreshold;
        j.minVerifierScore = minVerifierScore;
        j.expiresAt = expiresAt;
        j.state = JobState.OPEN;

        jobStateIndex[jobId] = jobsByState[JobState.OPEN].length;
        jobsByState[JobState.OPEN].push(jobId);

        profiles[posterId].posterJobs++;

        emit JobPosted(jobId, posterId, workerAmount, verifierFeeEach, verifierCount);
    }

    function acceptBid(uint256 jobId, uint256 workerProfileId) external {
        uint256 posterId = _profileIdOf(msg.sender);
        Job storage j = jobs[jobId];
        if (j.posterId != posterId) revert NotPoster();
        if (j.state != JobState.OPEN) revert InvalidState(j.state);
        if (block.timestamp >= j.expiresAt) revert JobExpired();

        ActorProfile storage worker = profiles[workerProfileId];
        if (!worker.exists) revert ProfileNotFound();

        j.workerId = workerProfileId;
        _moveJobState(jobId, JobState.OPEN, JobState.ACTIVE);

        emit BidAccepted(jobId, workerProfileId);
    }

    function submitWork(uint256 jobId, bytes32 outputHash) external {
        uint256 callerId = _profileIdOf(msg.sender);
        Job storage j = jobs[jobId];
        if (j.workerId != callerId) revert NotWorker();
        if (j.state != JobState.ACTIVE) revert InvalidState(j.state);
        if (block.timestamp >= j.expiresAt) revert JobExpired();
        if (outputHash == bytes32(0)) revert ZeroHash();

        j.outputHash = outputHash;
        _moveJobState(jobId, JobState.ACTIVE, JobState.IN_REVIEW);

        profiles[callerId].workerJobs++;
        emit WorkSubmitted(jobId, outputHash);
    }

    function applyToVerify(uint256 jobId) external {
        uint256 verifierId = _profileIdOf(msg.sender);
        Job storage j = jobs[jobId];
        if (j.state != JobState.IN_REVIEW) revert InvalidState(j.state);
        if (block.timestamp >= j.expiresAt) revert JobExpired();
        if (profiles[verifierId].verifierScore < j.minVerifierScore) revert BelowMinReputation();
        if (isPendingVerifier[jobId][verifierId]) revert AlreadyApplied();
        if (isAssignedVerifier[jobId][verifierId]) revert AlreadyApplied();
        if (j.verifierIds.length >= j.verifierCount) revert VerifierSlotsFull();

        pendingVerifiers[jobId].push(verifierId);
        isPendingVerifier[jobId][verifierId] = true;

        emit VerifierApplied(jobId, verifierId);
    }

    function acceptVerifier(uint256 jobId, uint256 verifierProfileId) external {
        uint256 posterId = _profileIdOf(msg.sender);
        Job storage j = jobs[jobId];
        if (j.posterId != posterId) revert NotPoster();
        if (j.state != JobState.IN_REVIEW) revert InvalidState(j.state);
        if (!isPendingVerifier[jobId][verifierProfileId]) revert ProfileNotFound();
        if (j.verifierIds.length >= j.verifierCount) revert VerifierSlotsFull();

        ActorProfile storage v = profiles[verifierProfileId];
        if (v.verifierScore < j.minVerifierScore) revert BelowMinReputation();

        // Remove from pending list
        uint256[] storage pending = pendingVerifiers[jobId];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == verifierProfileId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
        isPendingVerifier[jobId][verifierProfileId] = false;

        j.verifierIds.push(verifierProfileId);
        isAssignedVerifier[jobId][verifierProfileId] = true;
        v.verifierJobs++;

        emit VerifierAccepted(jobId, verifierProfileId);
    }

    function updateAxlKey(string calldata newKey) external {
        uint256 profileId = _profileIdOf(msg.sender);
        if (bytes(newKey).length == 0) revert ZeroHash();
        profiles[profileId].axlPublicKey = newKey;
        emit AxlKeyUpdated(profileId, newKey);
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    function _profileIdOf(address addr) internal view returns (uint256 profileId) {
        profileId = addressToProfileId[addr];
        if (profileId == 0) revert NotRegistered();
    }

    function _moveJobState(uint256 jobId, JobState from, JobState to) internal {
        uint256[] storage arr = jobsByState[from];
        uint256 idx = jobStateIndex[jobId];
        uint256 last = arr[arr.length - 1];
        arr[idx] = last;
        jobStateIndex[last] = idx;
        arr.pop();

        jobStateIndex[jobId] = jobsByState[to].length;
        jobsByState[to].push(jobId);
        jobs[jobId].state = to;
    }

    function _clampScore(int32 score) internal pure returns (uint16) {
        if (score < 0) return 0;
        if (score > int32(uint32(MAX_SCORE))) return MAX_SCORE;
        return uint16(uint32(score));
    }

    function _updateWorkerRep(uint256 profileId, bool passed) internal {
        ActorProfile storage p = profiles[profileId];
        int32 current = int32(uint32(p.workerScore));
        int32 delta = passed ? int32(WORKER_PASS_DELTA) : int32(WORKER_FAIL_DELTA);
        p.workerScore = _clampScore(current + delta);
        emit ReputationUpdated(profileId, "worker", p.workerScore);
    }

    function _updateVerifierRep(uint256 profileId, bool withMajority) internal {
        ActorProfile storage p = profiles[profileId];
        int32 current = int32(uint32(p.verifierScore));
        int32 delta = withMajority ? int32(VERIFIER_MAJORITY_DELTA) : int32(VERIFIER_MINORITY_DELTA);
        p.verifierScore = _clampScore(current + delta);
        emit ReputationUpdated(profileId, "verifier", p.verifierScore);
    }

    function _updatePosterRep(uint256 profileId, bool resolved) internal {
        ActorProfile storage p = profiles[profileId];
        int32 current = int32(uint32(p.posterScore));
        int32 delta = resolved ? int32(POSTER_RESOLVE_DELTA) : int32(POSTER_EXPIRE_DELTA);
        p.posterScore = _clampScore(current + delta);
        emit ReputationUpdated(profileId, "poster", p.posterScore);
    }
}
