# ADR-010: Single contract — no separate profile registry

**Status:** Accepted

## Decision

All logic (profiles, jobs, escrow, reputation) lives in one `LoafEscrow.sol`. No separate `ProfileRegistry` contract.

## Reasoning

- One deployment transaction, one ABI for `loaf-slice` to import.
- No cross-contract calls = no reentrancy surface between profile and escrow logic.
- Simpler to test: one contract under test, one mock USDC.
- Hackathon constraint: minimise setup steps.

## Consequences

- Single large contract — but Solidity's 24kb limit is not approached given the scope.
- Reputation is tied to the escrow contract address; a redeployment loses all profile data (accepted per ADR-004).
- If a separate registry were added later, it would require a migration path.
