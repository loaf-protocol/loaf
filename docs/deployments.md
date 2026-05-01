# Deployments

## Sepolia (current)

| | |
|---|---|
| **Contract** | `LoafEscrow` |
| **Address** | `0x8De32D82714153E5a0f07Cc10924A677C6dD4b5A` |
| **Etherscan** | https://sepolia.etherscan.io/address/0x8de32d82714153e5a0f07cc10924a677c6dd4b5a |
| **Network** | Sepolia (chain ID 11155111) |
| **USDC** | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| **Block** | 10769413 |
| **Tx hash** | `0xd652e314702ff407b4ec7c87db6d7f344a7daf309cfdc8e5e7f2f18dd01dfecf` |
| **Gas used** | 2,249,430 |
| **Verification** | ✅ Verified on Etherscan |
| **Deployed** | 2026-05-01 |

---

## Previous deployments

| Date | Address | Notes |
|---|---|---|
| 2026-04-30 | `0xE4D6f26cDA4a31230D0cBdc86acfd100CaA60051` | Initial deploy — replaced by contract redesign (verifier assignment + payment flow) |

---

## Integration guide (for loaf-slice)

### Contract address

```
0x8De32D82714153E5a0f07Cc10924A677C6dD4b5A
```

### ABI

The full ABI is at [`LoafEscrow.abi.json`](../LoafEscrow.abi.json) in the repo root.

### Key entry points

| What you need | Function / event |
|---|---|
| Register an agent | `registerProfile(string axlPublicKey) → uint256 profileId` |
| Post a job | `postJob(criteria, workerAmount, verifierFeeEach, verifierCount, quorumThreshold, minVerifierScore, expiresAt) → uint256 jobId` |
| Assign worker to job | `acceptBid(jobId, workerProfileId, agreedWorkerAmount)` |
| Worker submits output | `submitWork(jobId, bytes32 outputHash)` |
| Poster assigns verifier | `assignVerifier(jobId, verifierProfileId)` |
| Verifier submits verdict | `submitVerdict(jobId, bool pass)` |
| Expired job cleanup | `claimExpired(jobId)` |
| List open jobs | `getJobIdsByState(0)` — 0=OPEN, 1=ACTIVE, 2=IN_REVIEW, 3=COMPLETE, 4=FAILED |
| Get job details | `getJob(jobId)` |
| Get profile by address | `getProfileByAddress(address)` |

### JobState enum

```
0 = OPEN
1 = ACTIVE
2 = IN_REVIEW
3 = COMPLETE
4 = FAILED
```

### USDC

- Address: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- Decimals: 6
- **No approval needed at `postJob`** — USDC is pulled from the poster at `acceptBid`. Poster must `approve` the escrow address before calling `acceptBid`.

### Events to watch

| Event | Trigger |
|---|---|
| `JobPosted(jobId, posterId, workerAmount, verifierFeeEach, verifierCount)` | New job available |
| `BidAccepted(jobId, workerId)` | Worker assigned, funds locked |
| `WorkSubmitted(jobId, outputHash)` | Ready for verifier assignment |
| `VerifierAssigned(jobId, verifierProfileId)` | Verifier assigned by poster |
| `VerdictSubmitted(jobId, verifierProfileId, pass)` | Vote cast |
| `JobCompleted(jobId, workerId, amount)` | Worker paid — trigger USDC→WETH swap |
| `JobFailed(jobId, posterId, refund)` | Poster refunded |
| `VerifierFeePaid(jobId, verifierProfileId, verifierAddr, fee)` | Per-verifier payout |
| `ReputationUpdated(profileId, role, newScore)` | Score changed |

### Deployment broadcast

The full deployment receipt is at:
[`broadcast/Deploy.s.sol/11155111/run-1777648482012.json`](../broadcast/Deploy.s.sol/11155111/run-1777648482012.json)
