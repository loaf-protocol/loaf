# ADR-005: Verdicts submitted on-chain

**Status:** Accepted

## Decision

Each verifier calls `submitVerdict(jobId, bool pass)` directly. The contract auto-resolves when quorum is reached.

## Reasoning

- Trustless: contract enforces quorum math, not an off-chain process.
- Fully auditable: every verdict is an on-chain event.
- Enables KeeperHub bounty flow: KeeperHub bots can monitor `VerdictSubmitted` and nudge slow verifiers.

## Consequences

- ~50k gas per verdict × up to 10 verifiers.
- Auto-resolution fires inside `submitVerdict` when quorum is met — no separate settlement call needed.
