# ADR-009: Per-state job arrays for O(1) listing

**Status:** Accepted

## Decision

`mapping(JobState => uint256[]) jobsByState` + `mapping(uint256 => uint256) jobStateIndex` enables O(1) state transitions (swap-and-pop) and O(n_state) listings.

## Reasoning

- Without per-state arrays, `getOpenJobs()` would require iterating all `jobCount` entries — O(total_jobs).
- Swap-and-pop: when a job leaves a state, the last element takes its slot; index mapping is updated. One SSTORE per transition.
- `getJobIdsByState(JobState.OPEN)` returns only open jobs without any full scan.

## Consequences

- Results are unordered (swap-and-pop doesn't preserve insertion order).
- One extra `uint256` storage slot per job for the index (~20k gas one-time at postJob).
- `loaf-slice` must not rely on ordering of job lists.
