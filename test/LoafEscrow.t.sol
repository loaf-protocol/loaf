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
}
