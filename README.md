# regent-contracts

Canonical home for Regent Solidity source, Foundry tests, deployment scripts,
verified deployment records, canonical ABIs, and the chain-contract manifest.

- Layout: `src/{shared,techtree,staking,autolaunch}`, `test/`, `script/`,
  `deployments/{base-sepolia,base-mainnet}`, `contracts/chain-contracts.yaml`.
- Product repos keep HTTP/CLI contracts, Ash resources, workflow logic, UI,
  and projection workers.
- Required checks: `forge build`, `forge test`, `forge fmt --check`, Slither.
- Contract deployment is founder-gated; deploy scripts are prepared here and
  run only with explicit founder authorization.

First planned contract: `TechtreeGraphRegistryV1` (launch gate G4 — see
`control/docs/plans/regent-839.4-onchain-techtree-plan.md`).
