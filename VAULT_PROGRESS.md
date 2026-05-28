# Sato Stones Vault — progress memory (agent handoff)

> **Read this file first** after any context reset.  
> **Spec:** `_specs/sato-stones-vault-nft.md` simplified chunked draft.

## Essence

Vault NFT (2100 max): user locks **100–10k SATO** for **15/30/60d** during one global reward season. **2%** mint fee → one reward pool. **Early exit** → progressive penalty → pool/burn/prize/dev. After lock: **100% SATO back**, NFT stays. No special early-mint/Genesis tier.

## Current design decisions

- Only `seasonId = 0` exists.
- Mint closes at `t0 + SEASON_DURATION` (15 days) unless future code changes split mint duration from season duration.
- Season finalization is chunked: `finalizeSeason(0)` starts/default chunk; `processSeasonSnapshot(0, maxTokens)` continues.
- Season claims are lazy/pro-rata via `claimableSeasonAmount`; old precomputed `claimAmount` and wallet cap were removed for gas safety.
- Season eligibility is evaluated at `seasonEnd`, so 15-day Stones minted at `t0` are eligible.
- Prize draw snapshot is chunked: `requestPrizeDraw()` starts/default chunk; `processPrizeDrawSnapshot(maxTokens)` continues and sends VRF request on the final chunk.
- Prize eligibility is evaluated at `prizeSnapshotAt` (request-time), not per chunk.
- Redeem/early-exit/transfers are paused after season end until finalization completes, and during prize snapshots, to keep snapshots stable.

## Verification status

- [x] `forge test -vv --gas-limit 30000000000` — 16/16 passed.
- [x] Full-supply chunk tests: 2,100 Stones season finalization and prize snapshot pass with each chunk asserted under 25M gas.
- [x] `npm run compile:vault`.
- [x] `npm run vault:dry-run`.
- [x] JS syntax checks for frontend and scripts.
- [x] `forge build --sizes`: runtime ~16.9 KB, healthy EIP-170 margin.

## Remaining pre-mainnet work

- [ ] Replace mock-compatible VRF interface with official Chainlink VRF v2.5 consumer base/interface and verify on testnet.
- [ ] Add solvency invariant/fuzz suite.
- [ ] Harden frontend token scanning with multicall or indexer.
- [ ] Decide explicitly whether 15-day mint window is the final launch product.
- [ ] Update deps / review npm audit advisories.
- [ ] External audit after final behavior is frozen.

## Key files

| Path | Purpose |
|---|---|
| `src/SatoStonesVault.sol` | Main vault NFT contract |
| `test/SatoStonesVault.t.sol` | Foundry tests |
| `web/app-vault.js` | Static ethers v6 frontend logic |
| `web/index.html` | App markup/copy |
| `_specs/sato-stones-vault-nft.md` | Contract/product spec |
| `_specs/sato-stones-frontend.md` | Frontend spec |
| `_specs/operations-runbook.md` | Keeper/operator runbook |

## Checks to run after edits

```bash
npm run compile:vault
npm run vault:dry-run
PATH=/root/.foundry/bin:$PATH forge test -vv --match-contract SatoStonesVault
node --check web/app-vault.js && node --check script/compile-vault.js && node --check script/deploy-sepolia-mocks.js && node --check script/deploy-mainnet.js
```

## Remaining pre-mainnet concerns

- External audit still required.
- VRF production/subscription setup still needs final validation.
- Season finalization and prize ticket snapshot still loop over token IDs; 2100 cap keeps it bounded, but gas should be benchmarked.
- Frontend still scans token IDs through public RPC; acceptable for MVP, but indexer/cache would be better.
