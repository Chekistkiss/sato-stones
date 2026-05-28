# Sato Stones project guide

## Purpose

Sato Stones is a Solidity/ERC721A vault NFT project: 2,100 max mints, users lock SATO for 15/30/60 days during one reward season, 2% mint fee feeds a single reward pool, early exits burn/route penalties, and a Chainlink VRF-style lottery pays from the penalty/unallocated prize pool. Special early-mint NFT mechanics have been removed.

## Read first

1. `README.md` — current repo layout and commands.
2. `VAULT_PROGRESS.md` — handoff/status, Sepolia addresses, TODOs.
3. `_specs/spec-index.md` — source-of-truth spec map.
4. `_specs/sato-stones-vault-nft.md` and `_specs/sato-stones-frontend.md` before changing contract/frontend behavior.

## Key files

- `src/SatoStonesVault.sol` — main vault NFT contract.
- `test/SatoStonesVault.t.sol` — Foundry tests.
- `script/compile-vault.js` — Node/solc compile to `artifacts/SatoStonesVault.json`.
- `script/deploy-sepolia-mocks.js` — Sepolia mock deploy/dry-run.
- `script/deploy-mainnet.js` — guarded mainnet deploy path.
- `web/app-vault.js`, `web/index.html`, `web/styles.css` — static ethers v6 frontend.
- `web/config.js` — committed public Sepolia config only; never put secrets/private RPC keys here.

## Working rules

- After contract or frontend behavior changes, update the relevant `_specs/` doc in the same change.
- Initialize submodules before compile/test: `git submodule update --init --recursive`.
- Preferred checks:
  - `npm run compile:vault`
  - `npm run vault:dry-run`
  - `PATH=/root/.foundry/bin:$PATH forge test -vv --match-contract SatoStonesVault`
  - `node --check web/app-vault.js && node --check script/compile-vault.js && node --check script/deploy-sepolia-mocks.js && node --check script/deploy-mainnet.js`
- Do not deploy mainnet without explicit user confirmation and valid `.env.mainnet`; `script/deploy-mainnet.js` requires `--confirm-mainnet`.

## Current understanding

- Simplified chunked design: only season `0` exists, minting closes at `t0 + SEASON_DURATION`, no special early-mint fields/counter/rank/multiplier, and season claims are lazy/pro-rata by eligible Stone weight.
- Gas blockers from the prior audit were addressed with chunked `processSeasonSnapshot(0, maxTokens)` and `processPrizeDrawSnapshot(maxTokens)`; full-supply 2,100-Stone tests pass with per-chunk gas under 25M.
- Known remaining pre-mainnet risks: official Chainlink VRF v2.5 integration, solvency invariant/fuzz coverage, frontend RPC/indexing scalability, fixed 15-day mint-window product decision, npm audit transitive advisories (`ethers`/`ws`, `solc`/`tmp`), and external audit.
