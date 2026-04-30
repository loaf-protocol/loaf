# ADR-003: Factory escrow — one contract, all jobs in a mapping

**Status:** Accepted

## Decision

A single `LoafEscrow` contract holds all jobs in `mapping(uint256 => Job)`. No per-job contracts.

## Reasoning

- Deploying a new contract per job costs 2–3M gas each — unfeasible for a demo with many jobs.
- One ABI, one address makes `loaf-slice` integration trivial.
- Per-state arrays (`mapping(JobState => uint256[])`) provide O(1) listing without O(total_jobs) scans.

## Consequences

- All USDC held in a single contract address (higher blast radius if exploited).
- `list_jobs` MCP tool filters by state using the per-state arrays.
