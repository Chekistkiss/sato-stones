# Sato Stones — Post-fix Audit Summary

> Date: 2026-05-28
> Scope: simplified single-season build after audit fixes in `src/SatoStonesVault.sol`, `web/app-vault.js`, tests, and specs.

## What the project is now

Sato Stones is a **single-season SATO vault NFT**:

- **ERC721A collection:** max 2,100 Stones.
- **Mint:** user locks SATO in a Stone during the 15-day mint/reward window.
- **Lock choices:** 15 / 30 / 60 days with higher reward weight for longer locks.
- **No Genesis / no special early tier.** Every Stone follows the same rules.
- **One reward season:** only `seasonId = 0` exists.
- **Rewards:** 2% mint fee + early-exit pool share go to the season pool; claims are pro-rata by locked Stone weight.
- **Early exit:** burns the NFT and routes penalty to season/prize/burn/dev.
- **Lottery:** penalty-funded prize pool, Chainlink-style VRF flow, request-time snapshot, pull claim via `claimPrize()`.
- **No owner/admin/upgrades.** Parameters are immutable at deploy.

## Fixed from previous audit

### Fixed C1 — `finalizeSeason` block-gas-limit DoS

Old design finalized the whole season in one transaction and became impossible around a few hundred Stones.

Now:

- `finalizeSeason(0)` processes a default chunk.
- `processSeasonSnapshot(0, maxTokens)` continues finalization in chunks.
- Snapshot progress is stored in `seasonProcessedUntil`.
- Season becomes finalized only after all token IDs are processed.
- Claims are **lazy** via `claimableSeasonAmount(0, tokenId)` instead of precomputing `claimAmount` for every token.

Full-supply test added:

- `test_ChunkedSeasonFinalizesFullSupply()` mints 2,100 Stones and finalizes in chunks.
- Each chunk is asserted below 25M gas.

### Fixed C2 — `requestPrizeDraw` block-gas-limit DoS

Old design snapshotted all lottery tickets in one transaction and broke at collection scale.

Now:

- `requestPrizeDraw()` starts a prize snapshot and processes a default chunk.
- `processPrizeDrawSnapshot(maxTokens)` continues snapshotting.
- VRF request is sent only after all token IDs are processed.
- `prizeSnapshotAt` stores the draw start timestamp, so chunked processing keeps request-time eligibility.
- Vault actions/transfers are paused during an active prize snapshot to keep ownership/eligibility stable.

Full-supply test added:

- `test_ChunkedPrizeSnapshotRequestsVrfForFullSupply()` mints 2,100 Stones, funds prize pool, snapshots in chunks, and reaches a VRF request.
- Each chunk is asserted below 25M gas.

### Fixed C3 — 15-day mint-at-t0 eligibility bug

Old design checked season eligibility against `block.timestamp` during finalization, so 15-day Stones minted at deploy were excluded after season end.

Now season eligibility uses `seasonEnd`:

```solidity
if (v.satoLocked == 0 || uint256(v.lockEnd) < seasonEnd) continue;
```

A Stone whose `lockEnd == seasonEnd` is eligible. Test added:

- `test_FifteenDayMintAtT0IsSeasonEligible()`.

### Partially addressed C4 — fixed 15-day mint window

The 15-day mint/reward window is still intentionally fixed by immutable code. This is now treated as a product decision, not a hidden bug:

- mint closes at `t0 + SEASON_DURATION`;
- no admin extension exists;
- docs and UI should continue presenting this as a short one-season drop.

If you want a longer sale, the next change should add separate immutable constructor params like `mintDuration` and `seasonDuration`.

### Fixed M1 — empty VRF words guard

`rawFulfillRandomWords` now rejects empty `randomWords` with `InvalidDrawRequest()`.

### Improved M6 — contract size

Runtime size dropped materially after replacing precomputed claim storage with lazy claims:

- `SatoStonesVault` runtime: **16,924 bytes**
- EIP-170 margin: **7,652 bytes**

## Intentional behavior changes

### Removed season wallet cap

The old 10% per-wallet season cap caused expensive accounting and precomputed `claimAmount`. The current version distributes season rewards purely pro-rata by token weight. This is simpler, cheaper, and aligned with the simplified one-season design, but it changes economics: a wallet can receive more than 10% of the season pool if it owns enough eligible weight.

If the cap is still required, implement it with per-wallet weight accumulation during chunked snapshot, not with O(n²) wallet scans.

### Redeem / early exit pause after season end until finalization

After season end and before `seasonFinalized[0]`, `redeem` and `earlyExit` revert with `SeasonTransferLocked()`. This freezes the eligible set while chunked finalization runs.

During active prize snapshot, transfers/redeem/early-exit are also paused to preserve request-time lottery eligibility.

### No-eligible prize draw no longer reverts

If a prize snapshot completes with no eligible tickets, the pending prize is returned to `prizeFund` and no VRF request is made.

## Current checks

Passed:

```bash
PATH=/root/.foundry/bin:$PATH forge test -vv --gas-limit 30000000000
npm run compile:vault
npm run vault:dry-run
node --check web/app-vault.js
node --check script/compile-vault.js
node --check script/deploy-sepolia-mocks.js
node --check script/deploy-mainnet.js
PATH=/root/.foundry/bin:$PATH forge build --sizes
```

Results:

- Foundry: **16 tests passed, 0 failed**
- Full-supply chunk tests: **2,100 Stones season finalize + prize snapshot pass**
- JS syntax: pass
- Compile/dry-run: pass
- Runtime size: 16,924 bytes

## Remaining risks before mainnet

### High — real Chainlink VRF integration still needs finalization

The repo still uses a local `IVRFCoordinatorV2Plus` interface and mock-compatible flow. Before mainnet, switch to the official Chainlink VRF v2.5 consumer base/interface and run a real testnet fulfillment.

### High — no external audit yet

The core gas blockers are fixed, but this is still unaudited Solidity controlling escrowed SATO. External audit remains required.

### Medium — no invariant suite yet

Add invariant/fuzz tests for solvency and lifecycle accounting:

```text
locked + season claim obligations + prizeFund + pendingDrawPrize + pendingPrize + devBalance <= contract SATO balance
```

### Medium — frontend still scans token IDs

The frontend still checks ownership/snapshots by looping token IDs over public RPC. At 2,100 this may be slow. Use multicall or an indexer before production traffic.

### Medium — dependencies still have npm advisories

`npm audit` previously reported moderate advisories in tooling dependencies (`ethers/ws`, `solc/tmp`). Update/pin before production deploy.

### Product decision — 15-day mint window

Still fixed. Confirm that this is the desired launch model.

## Current verdict

The project is now a **working single-season vault NFT MVP that scales on-chain to the full 2,100 supply for finalization and prize snapshots via chunking**.

It is **much closer to testnet/mainnet readiness** than the audited version, but I would still not deploy mainnet until Chainlink VRF is switched to the official integration, invariant tests are added, and the frontend indexing/RPC path is hardened.
