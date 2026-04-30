# ADR-006: USDC address is a constructor argument

**Status:** Accepted

## Decision

`LoafEscrow(address _usdc)` injects the USDC token address at deploy time. Not hardcoded.

## Reasoning

- Multiple USDC variants exist on Sepolia (Circle official, community forks); deployer must choose.
- Tests use `MockUSDC` — hardcoding a real address would break local tests.
- Makes the contract portable to mainnet or other networks without code changes.

## Consequences

- Deployer must provide the correct address via `USDC_ADDRESS` env var.
- Wrong address at deploy = broken contract (no on-chain guard against misconfiguration).
