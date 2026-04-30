# ADR-002: On-chain reputation as uint16 scores

**Status:** Accepted

## Decision

Store 0–500 scores on-chain as `uint16` per role (worker, verifier, poster). 250 = 2.5 stars displayed.

## Reasoning

- Posters need to gate verifiers by score at `applyToVerify` time — requires on-chain readable value.
- Events-only reputation is fragile: requires off-chain aggregation that can fall out of sync.
- 5-star display (0.0–5.0) is a UX requirement; `score / 100.0` maps cleanly.

## Consequences

- ~6 SSTOREs per settlement (~120k gas overhead); acceptable for a hackathon demo.
- `loaf-sizzler` can still read events to build richer off-chain reputation history.
- Reputation resets if the escrow contract is redeployed (trade-off accepted per ADR-004).
