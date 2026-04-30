// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LoafEscrow.sol";
import "./mocks/MockUSDC.sol";

contract LoafEscrowTest is Test {
    LoafEscrow escrow;
    MockUSDC usdc;

    address poster    = makeAddr("poster");
    address worker    = makeAddr("worker");
    address verifier1 = makeAddr("verifier1");
    address verifier2 = makeAddr("verifier2");
    address verifier3 = makeAddr("verifier3");
    address stranger  = makeAddr("stranger");

    uint256 constant WORKER_AMOUNT    = 100e6;  // 100 USDC
    uint256 constant VERIFIER_FEE     = 10e6;   // 10 USDC each
    uint8   constant VERIFIER_COUNT   = 3;
    uint8   constant QUORUM_THRESHOLD = 2;
    uint256 constant JOB_EXPIRY_OFFSET = 1 days;

    function setUp() public {
        usdc   = new MockUSDC();
        escrow = new LoafEscrow(address(usdc));

        // Fund actors
        usdc.mint(poster,    1000e6);
        usdc.mint(worker,    100e6);
        usdc.mint(verifier1, 100e6);
        usdc.mint(verifier2, 100e6);
        usdc.mint(verifier3, 100e6);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _register(address actor, string memory key) internal returns (uint256) {
        vm.prank(actor);
        return escrow.registerProfile(key);
    }

    function _registerAll() internal {
        _register(poster,    "axl-poster");
        _register(worker,    "axl-worker");
        _register(verifier1, "axl-v1");
        _register(verifier2, "axl-v2");
        _register(verifier3, "axl-v3");
    }

    function _postDefaultJob() internal returns (uint256 jobId) {
        _registerAll();
        vm.startPrank(poster);
        usdc.approve(address(escrow), type(uint256).max);
        jobId = escrow.postJob(
            "do the thing",
            WORKER_AMOUNT,
            VERIFIER_FEE,
            VERIFIER_COUNT,
            QUORUM_THRESHOLD,
            0,
            block.timestamp + JOB_EXPIRY_OFFSET
        );
        vm.stopPrank();
    }

    function _activeJob() internal returns (uint256 jobId) {
        jobId = _postDefaultJob();
        uint256 workerId = escrow.getProfileId(worker);
        vm.prank(poster);
        escrow.acceptBid(jobId, workerId);
    }

    function _inReviewJob() internal returns (uint256 jobId) {
        jobId = _activeJob();
        vm.prank(worker);
        escrow.submitWork(jobId, keccak256("output"));
    }

    function _acceptAllVerifiers(uint256 jobId) internal {
        uint256 v1Id = escrow.getProfileId(verifier1);
        uint256 v2Id = escrow.getProfileId(verifier2);
        uint256 v3Id = escrow.getProfileId(verifier3);

        vm.prank(verifier1); escrow.applyToVerify(jobId);
        vm.prank(verifier2); escrow.applyToVerify(jobId);
        vm.prank(verifier3); escrow.applyToVerify(jobId);

        vm.startPrank(poster);
        escrow.acceptVerifier(jobId, v1Id);
        escrow.acceptVerifier(jobId, v2Id);
        escrow.acceptVerifier(jobId, v3Id);
        vm.stopPrank();
    }

    function _readyForVerdicts() internal returns (uint256 jobId) {
        jobId = _inReviewJob();
        _acceptAllVerifiers(jobId);
    }

    // ── Profile: registerProfile ──────────────────────────────────────────────

    function test_registerProfile_success() public {
        uint256 id = _register(poster, "axl-key");
        assertEq(id, 1);
        assertEq(escrow.actorCount(), 1);
    }

    function test_registerProfile_incrementingIds() public {
        uint256 id1 = _register(poster,  "axl-poster");
        uint256 id2 = _register(worker,  "axl-worker");
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_registerProfile_initialScores() public {
        uint256 id = _register(poster, "axl-key");
        LoafEscrow.ActorProfile memory p = escrow.getProfile(id);
        assertEq(p.workerScore,   escrow.INITIAL_SCORE());
        assertEq(p.verifierScore, escrow.INITIAL_SCORE());
        assertEq(p.posterScore,   escrow.INITIAL_SCORE());
    }

    function test_registerProfile_initialJobCounts() public {
        uint256 id = _register(poster, "axl-key");
        LoafEscrow.ActorProfile memory p = escrow.getProfile(id);
        assertEq(p.workerJobs,   0);
        assertEq(p.verifierJobs, 0);
        assertEq(p.posterJobs,   0);
    }

    function test_registerProfile_revert_alreadyRegistered() public {
        _register(poster, "axl-key");
        vm.prank(poster);
        vm.expectRevert(LoafEscrow.AlreadyRegistered.selector);
        escrow.registerProfile("axl-key2");
    }

    function test_registerProfile_revert_emptyKey() public {
        vm.prank(poster);
        vm.expectRevert(LoafEscrow.ZeroHash.selector);
        escrow.registerProfile("");
    }

    // ── Profile: updateAxlKey ─────────────────────────────────────────────────

    function test_updateAxlKey_success() public {
        uint256 id = _register(poster, "axl-old");
        vm.prank(poster);
        escrow.updateAxlKey("axl-new");
        LoafEscrow.ActorProfile memory p = escrow.getProfile(id);
        assertEq(p.axlPublicKey, "axl-new");
    }

    function test_updateAxlKey_revert_notRegistered() public {
        vm.prank(stranger);
        vm.expectRevert(LoafEscrow.NotRegistered.selector);
        escrow.updateAxlKey("axl-new");
    }

    function test_updateAxlKey_revert_emptyKey() public {
        _register(poster, "axl-old");
        vm.prank(poster);
        vm.expectRevert(LoafEscrow.ZeroHash.selector);
        escrow.updateAxlKey("");
    }

    // ── postJob ───────────────────────────────────────────────────────────────

    function test_postJob_success() public {
        uint256 jobId = _postDefaultJob();
        assertEq(jobId, 1);
        assertEq(escrow.jobCount(), 1);
    }

    function test_postJob_addsToOpenArray() public {
        _postDefaultJob();
        assertEq(escrow.getJobCountByState(LoafEscrow.JobState.OPEN), 1);
        assertEq(escrow.getJobIdsByState(LoafEscrow.JobState.OPEN)[0], 1);
    }

    function test_postJob_locksUSDC() public {
        uint256 before = usdc.balanceOf(poster);
        _postDefaultJob();
        uint256 locked = WORKER_AMOUNT + (VERIFIER_FEE * VERIFIER_COUNT);
        assertEq(usdc.balanceOf(poster), before - locked);
        assertEq(usdc.balanceOf(address(escrow)), locked);
    }

    function test_postJob_incrementingIds() public {
        _postDefaultJob();
        vm.prank(poster);
        uint256 jobId2 = escrow.postJob("job2", WORKER_AMOUNT, VERIFIER_FEE, 1, 1, 0, block.timestamp + 1 days);
        assertEq(jobId2, 2);
    }

    function test_postJob_revert_notRegistered() public {
        vm.prank(stranger);
        vm.expectRevert(LoafEscrow.NotRegistered.selector);
        escrow.postJob("x", 1e6, 1e6, 1, 1, 0, block.timestamp + 1 days);
    }

    function test_postJob_revert_zeroAmount() public {
        _register(poster, "axl-poster");
        vm.prank(poster);
        vm.expectRevert(LoafEscrow.ZeroAmount.selector);
        escrow.postJob("x", 0, 1e6, 1, 1, 0, block.timestamp + 1 days);
    }

    function test_postJob_revert_zeroVerifierCount() public {
        _register(poster, "axl-poster");
        vm.prank(poster);
        vm.expectRevert(LoafEscrow.InvalidVerifierCount.selector);
        escrow.postJob("x", 1e6, 1e6, 0, 0, 0, block.timestamp + 1 days);
    }

    function test_postJob_revert_tooManyVerifiers() public {
        _register(poster, "axl-poster");
        usdc.mint(poster, 10000e6);
        vm.startPrank(poster);
        usdc.approve(address(escrow), type(uint256).max);
        vm.expectRevert(LoafEscrow.InvalidVerifierCount.selector);
        escrow.postJob("x", 1e6, 1e6, 11, 1, 0, block.timestamp + 1 days);
        vm.stopPrank();
    }

    function test_postJob_revert_invalidQuorum() public {
        _register(poster, "axl-poster");
        vm.startPrank(poster);
        usdc.approve(address(escrow), type(uint256).max);
        vm.expectRevert(LoafEscrow.InvalidQuorum.selector);
        escrow.postJob("x", 1e6, 1e6, 3, 4, 0, block.timestamp + 1 days);
        vm.stopPrank();
    }

    function test_postJob_revert_expiredDeadline() public {
        _register(poster, "axl-poster");
        vm.startPrank(poster);
        usdc.approve(address(escrow), type(uint256).max);
        vm.expectRevert(LoafEscrow.JobExpired.selector);
        escrow.postJob("x", 1e6, 1e6, 1, 1, 0, block.timestamp);
        vm.stopPrank();
    }

    function test_postJob_edgeCase_oneVerifier() public {
        _register(poster, "axl-poster");
        vm.startPrank(poster);
        usdc.approve(address(escrow), type(uint256).max);
        uint256 jobId = escrow.postJob("x", 1e6, 1e6, 1, 1, 0, block.timestamp + 1 days);
        vm.stopPrank();
        assertEq(jobId, 1);
    }

    function test_postJob_edgeCase_tenVerifiers() public {
        _register(poster, "axl-poster");
        usdc.mint(poster, 10000e6);
        vm.startPrank(poster);
        usdc.approve(address(escrow), type(uint256).max);
        uint256 jobId = escrow.postJob("x", 1e6, 1e6, 10, 10, 0, block.timestamp + 1 days);
        vm.stopPrank();
        assertEq(jobId, 1);
    }

    // ── acceptBid ─────────────────────────────────────────────────────────────

    function test_acceptBid_success() public {
        uint256 jobId = _postDefaultJob();
        uint256 workerId = escrow.getProfileId(worker);
        vm.prank(poster);
        escrow.acceptBid(jobId, workerId);
        LoafEscrow.Job memory j = escrow.getJob(jobId);
        assertEq(j.workerId, workerId);
        assertEq(uint8(j.state), uint8(LoafEscrow.JobState.ACTIVE));
    }

    function test_acceptBid_movesStateArray() public {
        uint256 jobId = _postDefaultJob();
        uint256 workerId = escrow.getProfileId(worker);
        vm.prank(poster);
        escrow.acceptBid(jobId, workerId);
        assertEq(escrow.getJobCountByState(LoafEscrow.JobState.OPEN), 0);
        assertEq(escrow.getJobCountByState(LoafEscrow.JobState.ACTIVE), 1);
    }

    function test_acceptBid_revert_notPoster() public {
        uint256 jobId = _postDefaultJob();
        uint256 workerId = escrow.getProfileId(worker);
        vm.prank(stranger);
        vm.expectRevert(LoafEscrow.NotRegistered.selector);
        escrow.acceptBid(jobId, workerId);
    }

    function test_acceptBid_revert_wrongState() public {
        uint256 jobId = _activeJob();
        uint256 workerId = escrow.getProfileId(worker);
        vm.prank(poster);
        vm.expectRevert(abi.encodeWithSelector(LoafEscrow.InvalidState.selector, LoafEscrow.JobState.ACTIVE));
        escrow.acceptBid(jobId, workerId);
    }

    function test_acceptBid_revert_expired() public {
        uint256 jobId = _postDefaultJob();
        uint256 workerId = escrow.getProfileId(worker);
        vm.warp(block.timestamp + JOB_EXPIRY_OFFSET + 1);
        vm.prank(poster);
        vm.expectRevert(LoafEscrow.JobExpired.selector);
        escrow.acceptBid(jobId, workerId);
    }

    function test_acceptBid_revert_profileNotFound() public {
        uint256 jobId = _postDefaultJob();
        vm.prank(poster);
        vm.expectRevert(LoafEscrow.ProfileNotFound.selector);
        escrow.acceptBid(jobId, 999);
    }

    // ── submitWork ────────────────────────────────────────────────────────────

    function test_submitWork_success() public {
        uint256 jobId = _activeJob();
        bytes32 hash = keccak256("output");
        vm.prank(worker);
        escrow.submitWork(jobId, hash);
        LoafEscrow.Job memory j = escrow.getJob(jobId);
        assertEq(j.outputHash, hash);
        assertEq(uint8(j.state), uint8(LoafEscrow.JobState.IN_REVIEW));
    }

    function test_submitWork_movesStateArray() public {
        uint256 jobId = _activeJob();
        vm.prank(worker);
        escrow.submitWork(jobId, keccak256("output"));
        assertEq(escrow.getJobCountByState(LoafEscrow.JobState.ACTIVE), 0);
        assertEq(escrow.getJobCountByState(LoafEscrow.JobState.IN_REVIEW), 1);
    }

    function test_submitWork_revert_notWorker() public {
        uint256 jobId = _activeJob();
        vm.prank(stranger);
        vm.expectRevert(LoafEscrow.NotRegistered.selector);
        escrow.submitWork(jobId, keccak256("output"));
    }

    function test_submitWork_revert_wrongState() public {
        uint256 jobId = _inReviewJob();
        vm.prank(worker);
        vm.expectRevert(abi.encodeWithSelector(LoafEscrow.InvalidState.selector, LoafEscrow.JobState.IN_REVIEW));
        escrow.submitWork(jobId, keccak256("output2"));
    }

    function test_submitWork_revert_expired() public {
        uint256 jobId = _activeJob();
        vm.warp(block.timestamp + JOB_EXPIRY_OFFSET + 1);
        vm.prank(worker);
        vm.expectRevert(LoafEscrow.JobExpired.selector);
        escrow.submitWork(jobId, keccak256("output"));
    }

    function test_submitWork_revert_zeroHash() public {
        uint256 jobId = _activeJob();
        vm.prank(worker);
        vm.expectRevert(LoafEscrow.ZeroHash.selector);
        escrow.submitWork(jobId, bytes32(0));
    }

    // ── applyToVerify ─────────────────────────────────────────────────────────

    function test_applyToVerify_success() public {
        uint256 jobId = _inReviewJob();
        uint256 v1Id  = escrow.getProfileId(verifier1);
        vm.prank(verifier1);
        escrow.applyToVerify(jobId);
        uint256[] memory pending = escrow.getPendingVerifiers(jobId);
        assertEq(pending.length, 1);
        assertEq(pending[0], v1Id);
    }

    function test_applyToVerify_revert_notRegistered() public {
        uint256 jobId = _inReviewJob();
        vm.prank(stranger);
        vm.expectRevert(LoafEscrow.NotRegistered.selector);
        escrow.applyToVerify(jobId);
    }

    function test_applyToVerify_revert_wrongState() public {
        uint256 jobId = _activeJob();
        vm.prank(verifier1);
        vm.expectRevert(abi.encodeWithSelector(LoafEscrow.InvalidState.selector, LoafEscrow.JobState.ACTIVE));
        escrow.applyToVerify(jobId);
    }

    function test_applyToVerify_revert_expired() public {
        uint256 jobId = _inReviewJob();
        vm.warp(block.timestamp + JOB_EXPIRY_OFFSET + 1);
        vm.prank(verifier1);
        vm.expectRevert(LoafEscrow.JobExpired.selector);
        escrow.applyToVerify(jobId);
    }

    function test_applyToVerify_revert_belowMinReputation() public {
        uint256 jobId = _inReviewJob();
        // Post a job requiring high reputation
        _register(stranger, "axl-stranger");
        vm.startPrank(poster);
        uint256 highRepJobId = escrow.postJob("hard job", WORKER_AMOUNT, VERIFIER_FEE, 1, 1, 400, block.timestamp + 1 days);
        vm.stopPrank();
        uint256 strangerId = escrow.getProfileId(stranger);
        // Accept bid and submit work to get to IN_REVIEW
        vm.prank(poster); escrow.acceptBid(highRepJobId, strangerId);
        vm.prank(stranger); escrow.submitWork(highRepJobId, keccak256("out"));
        // verifier1 has score 250 < 400
        vm.prank(verifier1);
        vm.expectRevert(LoafEscrow.BelowMinReputation.selector);
        escrow.applyToVerify(highRepJobId);
        // suppress unused variable warning
        (jobId);
    }

    function test_applyToVerify_revert_alreadyApplied() public {
        uint256 jobId = _inReviewJob();
        vm.prank(verifier1);
        escrow.applyToVerify(jobId);
        vm.prank(verifier1);
        vm.expectRevert(LoafEscrow.AlreadyApplied.selector);
        escrow.applyToVerify(jobId);
    }

    function test_applyToVerify_revert_slotsFull() public {
        uint256 jobId = _inReviewJob();
        // job has 3 slots; fill all then try a 4th
        address v4 = makeAddr("verifier4");
        usdc.mint(v4, 100e6);
        _register(v4, "axl-v4");
        _acceptAllVerifiers(jobId);
        vm.prank(v4);
        vm.expectRevert(LoafEscrow.VerifierSlotsFull.selector);
        escrow.applyToVerify(jobId);
    }

    // ── acceptVerifier ────────────────────────────────────────────────────────

    function test_acceptVerifier_success() public {
        uint256 jobId = _inReviewJob();
        uint256 v1Id  = escrow.getProfileId(verifier1);
        vm.prank(verifier1); escrow.applyToVerify(jobId);
        vm.prank(poster);    escrow.acceptVerifier(jobId, v1Id);
        uint256[] memory assigned = escrow.getVerifierIds(jobId);
        assertEq(assigned.length, 1);
        assertEq(assigned[0], v1Id);
        assertEq(escrow.getPendingVerifiers(jobId).length, 0);
    }

    function test_acceptVerifier_revert_notPoster() public {
        uint256 jobId = _inReviewJob();
        uint256 v1Id  = escrow.getProfileId(verifier1);
        vm.prank(verifier1); escrow.applyToVerify(jobId);
        vm.prank(worker);
        vm.expectRevert(LoafEscrow.NotPoster.selector);
        escrow.acceptVerifier(jobId, v1Id);
    }

    function test_acceptVerifier_revert_notPending() public {
        uint256 jobId = _inReviewJob();
        uint256 v1Id  = escrow.getProfileId(verifier1);
        vm.prank(poster);
        vm.expectRevert(LoafEscrow.ProfileNotFound.selector);
        escrow.acceptVerifier(jobId, v1Id);
    }

    function test_acceptVerifier_revert_wrongState() public {
        uint256 jobId = _postDefaultJob();
        uint256 v1Id  = escrow.getProfileId(verifier1);
        vm.prank(poster);
        vm.expectRevert(abi.encodeWithSelector(LoafEscrow.InvalidState.selector, LoafEscrow.JobState.OPEN));
        escrow.acceptVerifier(jobId, v1Id);
    }

    function test_acceptVerifier_revert_belowMinReputation() public {
        // Post a job with high minVerifierScore
        _registerAll();
        vm.startPrank(poster);
        usdc.approve(address(escrow), type(uint256).max);
        uint256 jobId = escrow.postJob("hard", WORKER_AMOUNT, VERIFIER_FEE, 1, 1, 400, block.timestamp + 1 days);
        vm.stopPrank();
        uint256 workerId = escrow.getProfileId(worker);
        vm.prank(poster); escrow.acceptBid(jobId, workerId);
        vm.prank(worker); escrow.submitWork(jobId, keccak256("out"));

        uint256 v1Id = escrow.getProfileId(verifier1);
        vm.prank(verifier1);
        vm.expectRevert(LoafEscrow.BelowMinReputation.selector);
        escrow.applyToVerify(jobId);
        // suppress unused variable
        (v1Id);
    }

    function test_acceptVerifier_revert_slotsFull() public {
        uint256 jobId = _inReviewJob();
        uint256 v1Id  = escrow.getProfileId(verifier1);
        uint256 v2Id  = escrow.getProfileId(verifier2);
        uint256 v3Id  = escrow.getProfileId(verifier3);
        address v4    = makeAddr("verifier4");
        _register(v4, "axl-v4");
        uint256 v4Id  = escrow.getProfileId(v4);

        vm.prank(verifier1); escrow.applyToVerify(jobId);
        vm.prank(verifier2); escrow.applyToVerify(jobId);
        vm.prank(verifier3); escrow.applyToVerify(jobId);
        vm.prank(v4);        escrow.applyToVerify(jobId);

        vm.startPrank(poster);
        escrow.acceptVerifier(jobId, v1Id);
        escrow.acceptVerifier(jobId, v2Id);
        escrow.acceptVerifier(jobId, v3Id);
        vm.expectRevert(LoafEscrow.VerifierSlotsFull.selector);
        escrow.acceptVerifier(jobId, v4Id);
        vm.stopPrank();
    }

    // ── submitVerdict ─────────────────────────────────────────────────────────

    function test_submitVerdict_quorumPass() public {
        uint256 jobId    = _readyForVerdicts();
        uint256 workerId = escrow.getProfileId(worker);
        uint256 posterId = escrow.getProfileId(poster);

        uint256 workerBefore = usdc.balanceOf(worker);
        uint256 v1Before     = usdc.balanceOf(verifier1);
        uint16  workerScoreBefore = escrow.getProfile(workerId).workerScore;
        uint16  posterScoreBefore = escrow.getProfile(posterId).posterScore;

        vm.prank(verifier1); escrow.submitVerdict(jobId, true);
        vm.prank(verifier2); escrow.submitVerdict(jobId, true);

        // Quorum of 2 reached — job should be COMPLETE
        LoafEscrow.Job memory j = escrow.getJob(jobId);
        assertEq(uint8(j.state), uint8(LoafEscrow.JobState.COMPLETE));

        // Worker paid
        assertEq(usdc.balanceOf(worker), workerBefore + WORKER_AMOUNT);
        // Verifiers paid (both voted, v3 not yet but quorum triggered payout for all assigned)
        assertEq(usdc.balanceOf(verifier1), v1Before + VERIFIER_FEE);

        // Worker rep +20
        assertEq(escrow.getProfile(workerId).workerScore, workerScoreBefore + 20);
        // Poster rep +10
        assertEq(escrow.getProfile(posterId).posterScore, posterScoreBefore + 10);
    }

    function test_submitVerdict_quorumFail() public {
        uint256 jobId    = _readyForVerdicts();
        uint256 posterId = escrow.getProfileId(poster);
        uint256 workerId = escrow.getProfileId(worker);

        uint256 posterBefore      = usdc.balanceOf(poster);
        uint16  workerScoreBefore = escrow.getProfile(workerId).workerScore;

        vm.prank(verifier1); escrow.submitVerdict(jobId, false);
        vm.prank(verifier2); escrow.submitVerdict(jobId, false);

        // 2 fail votes > (3 - 2) = 1 → FAILED
        LoafEscrow.Job memory j = escrow.getJob(jobId);
        assertEq(uint8(j.state), uint8(LoafEscrow.JobState.FAILED));

        // Poster gets workerAmount back
        assertEq(usdc.balanceOf(poster), posterBefore + WORKER_AMOUNT);
        // Worker rep -30
        assertEq(escrow.getProfile(workerId).workerScore, workerScoreBefore - 30);
        // Poster rep +10
        assertEq(escrow.getProfile(posterId).posterScore, escrow.INITIAL_SCORE() + 10);
    }

    function test_submitVerdict_singleVerifier_pass() public {
        _registerAll();
        vm.startPrank(poster);
        usdc.approve(address(escrow), type(uint256).max);
        uint256 jobId = escrow.postJob("x", WORKER_AMOUNT, VERIFIER_FEE, 1, 1, 0, block.timestamp + 1 days);
        vm.stopPrank();

        uint256 workerId = escrow.getProfileId(worker);
        uint256 v1Id     = escrow.getProfileId(verifier1);

        vm.prank(poster);    escrow.acceptBid(jobId, workerId);
        vm.prank(worker);    escrow.submitWork(jobId, keccak256("out"));
        vm.prank(verifier1); escrow.applyToVerify(jobId);
        vm.prank(poster);    escrow.acceptVerifier(jobId, v1Id);

        uint256 workerBefore = usdc.balanceOf(worker);
        vm.prank(verifier1); escrow.submitVerdict(jobId, true);

        assertEq(uint8(escrow.getJob(jobId).state), uint8(LoafEscrow.JobState.COMPLETE));
        assertEq(usdc.balanceOf(worker), workerBefore + WORKER_AMOUNT);
    }

    function test_submitVerdict_verifierPaidRegardlessOfOutcome() public {
        uint256 jobId = _readyForVerdicts();
        uint256 v1Before = usdc.balanceOf(verifier1);
        uint256 v2Before = usdc.balanceOf(verifier2);
        uint256 v3Before = usdc.balanceOf(verifier3);

        vm.prank(verifier1); escrow.submitVerdict(jobId, true);
        vm.prank(verifier2); escrow.submitVerdict(jobId, true);
        // Quorum passes at v2 — all 3 assigned verifiers paid on resolution
        assertEq(usdc.balanceOf(verifier1), v1Before + VERIFIER_FEE);
        assertEq(usdc.balanceOf(verifier2), v2Before + VERIFIER_FEE);
        assertEq(usdc.balanceOf(verifier3), v3Before + VERIFIER_FEE);
    }

    function test_submitVerdict_reputationMajority() public {
        uint256 jobId = _readyForVerdicts();
        uint256 v1Id  = escrow.getProfileId(verifier1);
        uint256 v2Id  = escrow.getProfileId(verifier2);
        uint256 v3Id  = escrow.getProfileId(verifier3);

        // v1 and v2 vote pass (majority), v3 votes fail (minority — but quorum triggers before v3 votes)
        vm.prank(verifier1); escrow.submitVerdict(jobId, true);
        vm.prank(verifier2); escrow.submitVerdict(jobId, true);

        // v1, v2 voted pass = majority (pass outcome)
        assertEq(escrow.getProfile(v1Id).verifierScore, escrow.INITIAL_SCORE() + 10);
        assertEq(escrow.getProfile(v2Id).verifierScore, escrow.INITIAL_SCORE() + 10);
        // v3 hasn't voted yet but was assigned and still gets majority (didn't vote against)
        assertEq(escrow.getProfile(v3Id).verifierScore, escrow.INITIAL_SCORE() + 10);
    }

    function test_submitVerdict_reputationMinority() public {
        uint256 jobId = _readyForVerdicts();
        uint256 v1Id  = escrow.getProfileId(verifier1);
        uint256 v2Id  = escrow.getProfileId(verifier2);

        // v1 votes fail, v2+v3 vote pass (quorum at v3)
        vm.prank(verifier1); escrow.submitVerdict(jobId, false);
        vm.prank(verifier2); escrow.submitVerdict(jobId, true);
        vm.prank(verifier3); escrow.submitVerdict(jobId, true);

        // pass outcome: v1 voted fail → minority
        assertEq(escrow.getProfile(v1Id).verifierScore, escrow.INITIAL_SCORE() - 20);
        // v2 voted pass → majority
        assertEq(escrow.getProfile(v2Id).verifierScore, escrow.INITIAL_SCORE() + 10);
    }

    function test_submitVerdict_stateArrayMoves() public {
        uint256 jobId = _readyForVerdicts();
        assertEq(escrow.getJobCountByState(LoafEscrow.JobState.IN_REVIEW), 1);
        vm.prank(verifier1); escrow.submitVerdict(jobId, true);
        vm.prank(verifier2); escrow.submitVerdict(jobId, true);
        assertEq(escrow.getJobCountByState(LoafEscrow.JobState.IN_REVIEW), 0);
        assertEq(escrow.getJobCountByState(LoafEscrow.JobState.COMPLETE), 1);
    }

    function test_submitVerdict_revert_notVerifier() public {
        uint256 jobId = _readyForVerdicts();
        vm.prank(stranger);
        vm.expectRevert(LoafEscrow.NotRegistered.selector);
        escrow.submitVerdict(jobId, true);
    }

    function test_submitVerdict_revert_alreadyVoted() public {
        uint256 jobId = _readyForVerdicts();
        vm.prank(verifier1); escrow.submitVerdict(jobId, true);
        vm.prank(verifier1);
        vm.expectRevert(LoafEscrow.AlreadyVoted.selector);
        escrow.submitVerdict(jobId, true);
    }

    function test_submitVerdict_revert_wrongState() public {
        uint256 jobId = _activeJob();
        vm.prank(verifier1);
        vm.expectRevert(abi.encodeWithSelector(LoafEscrow.InvalidState.selector, LoafEscrow.JobState.ACTIVE));
        escrow.submitVerdict(jobId, true);
    }
}
