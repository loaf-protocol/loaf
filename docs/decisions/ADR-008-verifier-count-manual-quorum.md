# ADR-008: Verifier count 1–10, manual quorum, no tie-prevention

**Status:** Accepted

## Decision

Poster explicitly sets `verifierCount` (1–10) and `quorumThreshold` (1–verifierCount). No odd-only restriction.

## Reasoning

- Threshold system resolves on first threshold hit — ties are impossible by construction:
  - Pass resolves when `passVotes >= threshold`.
  - Fail resolves when `failVotes > count - threshold`.
  - These conditions are mutually exclusive for any valid threshold.
- Removing odd-only restriction gives poster full control over quorum shape (e.g. unanimous 3-of-3, simple majority 2-of-3, supermajority 4-of-5).
- Loop cap of 10 keeps gas bounded.

## Consequences

- Poster bears full responsibility for choosing a sensible quorum.
- A threshold of `count` (unanimous) means the job can only fail if `failVotes > 0` (impossible if all pass) — effectively pass-only.
