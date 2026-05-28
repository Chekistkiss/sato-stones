# Sato Stones — Vault NFT Specification

> Version: simplified single-season, chunked snapshot draft
> Chain: Ethereum Mainnet / Sepolia testing

## 1. Overview

Sato Stones is a 2,100 supply ERC721A vault NFT. Each Stone locks SATO in escrow. The user chooses:

- gross deposit: **100–10,000 SATO** subject to the dynamic cap;
- lock period: **15 / 30 / 60 days**.

The simplified design has exactly **one reward season**: `seasonId = 0`. There is **no special early-mint NFT tier**, no early-mint counter, no early-mint rank, and no early-mint weight multiplier.

## 2. Mint

```text
mint(grossAmount, lockDays)
```

Rules:

- Revert if `totalMintedEver >= 2100`.
- Revert if wallet already minted `MAX_MINTS_PER_WALLET`.
- Revert after the single reward season ends: `block.timestamp >= t0 + SEASON_DURATION`.
- Revert if `grossAmount < 100 SATO` or above `maxGrossForMint()`.
- Pull SATO from caller.
- `mintFee = received * 200 / 10_000` goes to `seasonPool[0]`.
- `peakSato = received - mintFee` is escrowed in the vault.
- `weightAtMint = sqrt(peakSato) × lockMultiplier`.
- Mint exactly one NFT.

Lock multipliers:

| Lock | Multiplier | Base early-exit penalty |
|---|---:|---:|
| 15 days | 1.0× | 30% scaled by remaining days |
| 30 days | 1.8× | 25% scaled by remaining days |
| 60 days | 3.0× | 20% scaled by remaining days |

## 3. Redeem / early exit

After lock end, the current NFT owner can call `redeem(tokenId)`:

- returns 100% of `satoLocked`;
- marks the vault redeemed;
- keeps the NFT alive as an empty collectible.

Before lock end, the owner can call `earlyExit(tokenId)`:

- computes a progressive penalty by remaining partial days, rounded up;
- returns `satoLocked - penalty`;
- burns the NFT;
- routes penalty:
  - 48% to reward pool before finalization, or to prize fund after finalization;
  - 33% burn to `DEAD`;
  - 15% prize fund;
  - 2% dev;
  - remaining dust to reward pool before finalization, or prize fund after finalization.

After season end and before `seasonFinalized[0]`, redeem and early exit are paused so the season snapshot cannot be mutated mid-finalization. They are also paused during an active prize snapshot.

## 4. One reward season

Only `seasonId = 0` is valid.

```text
currentSeasonId() = 0
seasonEnd = t0 + SEASON_DURATION
```

Season finalization is chunked:

```text
finalizeSeason(0)                         // default chunk
processSeasonSnapshot(0, maxTokens)       // explicit chunk size
```

Finalization:

1. Callable after `seasonEnd` and only once.
2. First chunk stores `seasonDistributable = seasonPool[0]` and sets `seasonPool[0] = 0`.
3. Each chunk snapshots owners and adds weights for token IDs in its range.
4. Eligibility is checked at `seasonEnd`, not at the chunk's block time:
   - eligible if `satoLocked > 0` and `lockEnd >= seasonEnd`.
5. When all token IDs are processed, set `seasonFinalized[0] = true`.
6. If total eligible weight is zero, move `seasonDistributable` to `prizeFund`.

Claims are lazy/pro-rata:

```text
claimableSeasonAmount(0, tokenId)
claimSeason(0, tokenId)
```

- requires finalized season;
- requires `msg.sender == snapshotOwner[0][tokenId]`;
- can be claimed once;
- amount is `seasonDistributable * weightAtMint / seasonTotalWeight[0]`.

There is currently **no per-wallet season cap**. If a cap is reintroduced, it must be implemented with chunked per-wallet accounting, not O(n²) scans.

## 5. Transfer lockout

Transfers are blocked:

- during the last hour before reward-season end while the season is not finalized;
- after season end until season finalization finishes;
- during an active prize snapshot.

Mint and burn are not normal wallet-to-wallet transfers and are not affected by the ERC721 hook, but minting also closes at season end and early exit is paused after season end until finalization.

## 6. Lottery

The prize fund is funded by:

- 15% of early-exit penalties;
- reward-pool share of early exits after the single season has already been finalized;
- zero-weight/unallocated season pool.

Prize draw is chunked:

```text
requestPrizeDraw()                 // starts snapshot and processes default chunk
processPrizeDrawSnapshot(maxTokens) // continues snapshot; final chunk sends VRF request
```

`requestPrizeDraw()` can start when:

- VRF coordinator is configured;
- no draw or prize snapshot is pending;
- `prizeFund >= prizeMinSato`;
- `block.timestamp >= lastPrizeDrawAt + prizeDrawInterval`.

The draw stores `prizeSnapshotAt = block.timestamp`. Eligibility across all chunks is checked at this request-time timestamp:

- eligible if token exists, `satoLocked > 0`, and `lockEnd > prizeSnapshotAt`.

During prize snapshot, transfers/redeem/early-exit are paused. If the snapshot completes with zero eligible tickets, the pending prize returns to `prizeFund` and no VRF request is made.

Winner receives `pendingPrize[winner]` and claims with `claimPrize()`.

## 7. Contract surface

```text
SatoStonesVault.sol
  mint(grossAmount, lockDays)
  earlyExit(tokenId)
  redeem(tokenId)
  finalizeSeason(0)
  processSeasonSnapshot(0, maxTokens)
  claimableSeasonAmount(0, tokenId)
  claimSeason(0, tokenId)
  requestPrizeDraw()
  processPrizeDrawSnapshot(maxTokens)
  rawFulfillRandomWords(requestId, words)
  recoverTimedOutPrizeDraw()
  claimPrize()
  withdrawDev()
  previewMint(grossAmount, lockDays)
  maxGrossForMint()
  getEarlyExitPenalty(tokenId)

Vault:
  peakSato
  satoLocked
  lockEnd
  weightAtMint
  lockDays
  rarity
  redeemed
```

## 8. Main invariants

- `totalMintedEver <= 2100`.
- Each token can be redeemed or early-exited at most once.
- Redeem returns exactly the locked `satoLocked` amount.
- Early exit burns the NFT and cannot reopen supply.
- Only season `0` can be finalized or claimed.
- A Stone minted at `t0` with a 15-day lock is eligible for the season because `lockEnd == seasonEnd`.
- No special early-mint storage, events, UI, or weight multiplier exists.
- Contract SATO accounting must cover locked balances, unclaimed rewards, pending prizes, prize fund, and dev balance.
