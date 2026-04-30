# ADR-004: Immutable contract — no proxy

**Status:** Accepted

## Decision

Plain deployment, no `TransparentProxy`, no UUPS. Bugs require redeployment.

## Reasoning

- Hackathon timeline: proxy patterns add setup complexity and audit surface.
- Etherscan verification is simpler for a non-proxied contract.
- Redeployment is acceptable — `loaf-slice` just updates the contract address env var.

## Consequences

- Any bug fix requires a new deployment and updating all downstream references.
- Reputation data is lost on redeployment (accepted trade-off per ADR-002).
