# ADR-001: Uniswap swap is external to the contract

**Status:** Accepted

## Decision

`LoafEscrow` releases USDC to the worker/poster/verifiers. The USDC→WETH swap is performed by `loaf-slice` after it detects `VerifierFeePaid` / `JobCompleted` events.

## Reasoning

- Embedding the Uniswap router couples the escrow contract to a specific DEX version and router address.
- Reentrancy surface increases significantly when calling external contracts mid-settlement.
- Simpler contract is easier to audit, test, and redeploy.

## Consequences

- `loaf-slice` must watch for settlement events and trigger swaps off-chain.
- Contract remains USDC-only; token conversion is fully decoupled.
