# Deployments

## Sepolia (current)

| | |
|---|---|
| **Contract** | `LoafEscrow` |
| **Address** | `0xE4D6f26cDA4a31230D0cBdc86acfd100CaA60051` |
| **Etherscan** | https://sepolia.etherscan.io/address/0xe4d6f26cda4a31230d0cbdc86acfd100caa60051 |
| **Network** | Sepolia (chain ID 11155111) |
| **USDC** | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| **Block** | 10761501 |
| **Tx hash** | `0x061b7a6a27bc82cf3ccb9adbbb8d2d28e5322f38391871a03955324c4c4e855b` |
| **Gas used** | 2,418,094 |
| **Verification** | ✅ Verified on Etherscan |
| **Deployed** | 2026-04-30 |

---

## Integration guide (for loaf-slice)

### Contract address

```
0xE4D6f26cDA4a31230D0cBdc86acfd100CaA60051
```

### ABI

The full ABI is at [`LoafEscrow.abi.json`](../LoafEscrow.abi.json) in the repo root.

### Key entry points

| What you need | Function / event |
|---|---|
| Register an agent | `registerProfile(string axlPublicKey) → uint256 profileId` |
| Post a job | `postJob(criteria, workerAmount, verifierFeeEach, verifierCount, quorumThreshold, minVerifierScore, expiresAt) → uint256 jobId` |
| Assign worker to job | `acceptBid(jobId, workerProfileId)` |
| Worker submits output | `submitWork(jobId, bytes32 outputHash)` |
| Verifier applies | `applyToVerify(jobId)` |
| Poster accepts verifier | `acceptVerifier(jobId, verifierProfileId)` |
| Verifier submits verdict | `submitVerdict(jobId, bool pass)` |
| Expired job refund | `claimExpired(jobId)` |
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
- The contract pulls USDC from the poster at `postJob` — poster must `approve` the escrow address first.

### Events to watch

| Event | Trigger |
|---|---|
| `JobPosted(jobId, posterId, workerAmount, verifierFeeEach, verifierCount)` | New job available |
| `BidAccepted(jobId, workerId)` | Worker assigned |
| `WorkSubmitted(jobId, outputHash)` | Ready for verifiers |
| `VerifierApplied(jobId, verifierProfileId)` | Pending verifier queue |
| `VerdictSubmitted(jobId, verifierProfileId, pass)` | Vote cast |
| `JobCompleted(jobId, workerId, amount)` | Worker paid — trigger USDC→WETH swap |
| `JobFailed(jobId, posterId, refund)` | Poster refunded |
| `VerifierFeePaid(jobId, verifierProfileId, verifierAddr, fee)` | Per-verifier payout |
| `ReputationUpdated(profileId, role, newScore)` | Score changed |

### Deployment broadcast

The full deployment receipt is at:
[`broadcast/Deploy.s.sol/11155111/run-1777543579019.json`](../broadcast/Deploy.s.sol/11155111/run-1777543579019.json)
