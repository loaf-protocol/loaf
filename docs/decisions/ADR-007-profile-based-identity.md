# ADR-007: Profile-based identity (profileId, not raw address)

**Status:** Accepted

## Decision

Actors are referenced internally by `profileId` (auto-incremented `uint256`), not by `address`. A single `registerProfile` call creates one profile reused across all three roles.

## Reasoning

- A single identity carries AXL key + all three reputation scores across roles.
- One registration call → all role capabilities unlocked (poster, worker, verifier).
- Consistent identity enables richer reputation history in `loaf-sizzler`.

## Consequences

- `registerProfile` is required before any other action.
- Functions incur a mapping lookup (`addressToProfileId[msg.sender]`) on every call.
- Profile ID 0 is reserved as the "not registered" sentinel — `actorCount` starts at 0 and increments before assignment.
