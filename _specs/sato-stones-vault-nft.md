# Sato Stones — Vault NFT Specification

> Version: 1.3  
> Status: Ready for development  
> Chain: Ethereum Mainnet (EVM)  
> Replaces the deprecated fixed-tier bonding-curve mint model.

---

## 1. Overview

Sato Stones — коллекция из **2100** NFT (ERC-721A) на Ethereum. Каждый NFT — **vault**: пользователь выбирает сумму SATO для lock и срок (15 / 30 / 60 дней). SATO хранится в escrow контракта.

**Ключевой принцип:** SATO **не продаётся** на bonding-curve при mint. Токены лочатся → TVL и scarcity. Досрочный exit платит штраф; из штрафа **2%** идёт dev, остальное — pool / burn / prize.

После окончания lock: **100% escrowed SATO** возвращается владельцу, NFT **остаётся** с зафиксированной редкостью (`peakSato`, tier, Genesis).

**Supply rule:** максимум **2100 mint ever**. `earlyExit` сжигает NFT, но **не** открывает новый слот для mint.

---

## 2. Fixed parameters (canonical)

| Parameter | Value |
|-----------|-------|
| Standard | ERC-721A |
| Max supply | **2100 total mints ever** (burn via `earlyExit` does not free a slot) |
| Min gross deposit (any mint) | 100 SATO |
| Genesis qualification | Gross deposit **≥ 500 SATO**; first **21** qualifying mints (FIFO) |
| `tokenId` | Sequential `#1…#2100` by mint order (independent of Genesis) |
| Max gross deposit per NFT | min(10_000 SATO, 0.1% SATO `totalSupply()` at mint) |
| Lock periods | **Only** 15 / 30 / 60 days (`enum`; other values revert) |
| Mint fee | 200 bps of **gross** deposit → current season pool |
| Escrow | `peakSato = gross × 9800 / 10_000` (fee-on-transfer safe, see §3) |
| Early-exit penalty | Progressive on **`peakSato`** (see §3) |
| Penalty split (of `penaltySato`) | 4800 pool / 3300 burn / 1500 prize / **200 dev** |
| Transfer during lock | Allowed except **last 1 hour** of each global season (§9) |
| After lock | `redeem()` → 100% `peakSato` remaining in vault; NFT kept |
| Weight (stored at mint) | `weightAtMint = sqrt(peakSato) × lockMultiplier × genesisMult` |
| Visual rarity | From `weightAtMint` at mint (§7) |
| Re-lock same NFT | Not allowed |
| Global seasons | 15 days from deploy `t0` |
| Season transfer lockout | Last **3600 seconds** before each season end: transfers revert |
| Max mints per wallet (lifetime) | 10 |
| Max pool claim per wallet per season | 10% of distributable amount (`MAX_CLAIM_BPS = 1000`) |
| Pool carryover | If `totalWeight == 0`, undistributed SATO → **next season** |
| SATO burn address | `0x000000000000000000000000000000000000dEaD` |
| `prizeMinSato` | Immutable (e.g. `50_000 ether` — set at deploy) |
| `drawInterval` | Immutable draw cadence (e.g. 30 days) |
| `PRIZE_DRAW_TIMEOUT` | 1 day; used only to recover a stuck pending VRF draw |
| VRF | Chainlink VRF v2.5-compatible `requestRandomWords(RandomWordsRequest)` + `rawFulfillRandomWords`; subscription funded at deploy (see §10) |
| Admin / pause / upgrade | None |

All BPS, caps, and addresses above are **immutable** in the constructor.

---

## 3. Mint intake, escrow, and penalties

### Fee-on-transfer safe intake

```text
balanceBefore = sato.balanceOf(this)
sato.safeTransferFrom(user, this, grossAmount)
received = sato.balanceOf(this) - balanceBefore
require(received >= grossAmount × 9800 / 10_000)   // tolerate small fee tokens; document if SATO fee-on-transfer
```

If SATO charges transfer fee, use **`received`** as effective gross for fee/escrow math.

### Escrow and peakSato

```text
mintFee      = gross × 200 / 10_000        → seasonPool[currentSeason]
peakSato     = gross - mintFee             (or received - mintFee)
lockEnd      = block.timestamp + lockDays × 1 days
weightAtMint = sqrt(peakSato) × lockMultiplier × genesisMult
```

### Progressive penalty (on `earlyExit`)

```text
require(block.timestamp < lockEnd)          // else use redeem()
daysRemaining = ceil((lockEnd - block.timestamp) / 1 days)
penaltyBps = basePenaltyBps[lock] × daysRemaining / lockDays
penaltySato = peakSato × penaltyBps / 10_000
userReceives = satoLocked - penaltySato     // satoLocked == peakSato until exit/redeem
```

| Lock | `lockMultiplier` | `basePenaltyBps` (day 1) |
|------|------------------|--------------------------|
| 15d | 1.0× | 3000 (30%) |
| 30d | 1.8× | 2500 (25%) |
| 60d | 3.0× | 2000 (20%) |

**Example tables** in v1.2 remain valid if **deposit = peakSato = 1000** (gross 1020.41… or gross 1000 with fee taken from gross: peakSato = 980).

**Penalty routing:** split `penaltySato` by 4800/3300/1500/200 bps (9800 bps explicit); remaining **200 bps** credited to **current season pool** with the 4800 bps portion; burn → `DEAD`.

### Mint constraints

- `quantity` per tx: **1** only in v1.3 (no batch mint).
- `totalMinted() < 2100` or revert `MintedOut`.

---

## 4. Genesis allocation

1. Next `tokenId = totalMinted() + 1` before mint.
2. If `gross >= 500 SATO` (effective received) and `genesisMinted < 21` → `isGenesis = true`, `genesisRank = ++genesisMinted`.
3. Else `isGenesis = false`, `genesisRank = 0`.
4. Gross `< 500` → never Genesis.

| Order | Gross | `tokenId` | Genesis |
|-------|-------|-----------|---------|
| 1st | 300 | #1 | No |
| 2nd | 500 | #2 | Genesis #1 |
| 3rd | 100 | #3 | No |

`genesisMult = 1.2` if `isGenesis`, else `1.0` — applied once into `weightAtMint`.

---

## 5. Lifecycle

```text
MINT → ACTIVE LOCK → (earlyExit | redeem) → (empty vault NFT if redeem)
```

| Step | Behavior |
|------|----------|
| **MINT** | Pull SATO, fee 2%, escrow `peakSato`, mint NFT, set `lockEnd`, `weightAtMint` |
| **ACTIVE LOCK** | `satoLocked == peakSato`; eligible for pool/lottery snapshots |
| **earlyExit** | Penalty on `peakSato`; split penalty; **burn NFT**; `totalMinted` unchanged; **no remint slot** |
| **redeem** | Requires `block.timestamp >= lockEnd`; return all `satoLocked`; `satoLocked = 0`; NFT kept |

---

## 6. Visual rarity and metadata

| `weightAtMint` | Tier | Visual |
|----------------|------|--------|
| 0 – 15 | Common | Grey stone |
| 15 – 50 | Uncommon | Blue stone |
| 50 – 150 | Rare | Purple stone |
| 150+ | Mythic | Gold stone |

- **Genesis:** separate frame / trait (`isGenesis`, `genesisRank`); not the same asset as Mythic recolor.
- Required fields: `tokenId`, `isGenesis`, `genesisRank`, `peakSatoLocked`, `lockDurationDays`, `rarityTier`, `status`.

**Post-redeem:** `status = redeemed`, `currentSatoLocked = 0`, `weightAtMint` unchanged for history; **no** pool/lottery eligibility.

---

## 7. Global seasons and community pool

### Season timing

```text
seasonId = (block.timestamp - t0) / (15 days)
seasonEnd[seasonId] = t0 + (seasonId + 1) × 15 days
```

### Pool inflows (accounting)

| Source | Credited to |
|--------|-------------|
| Mint fee (2% gross) | `seasonPool[seasonId_at_mint]` |
| 48% of `penaltySato` | `seasonPool[seasonId_at_exit]` |

`undistributedCarry` — SATO not distributed in a season: `totalWeight == 0`, or unclaimed remainder after wallet-cap claims (`distributable - sum(claimAmount)`). Added to the **next** season’s distributable amount.

### Transfer lockout (anti-gaming)

If `block.timestamp >= seasonEnd[seasonId] - 3600` and `< seasonEnd[seasonId]`:

- `_update` / transfer hooks **revert** `SeasonTransferLocked`.

### Finalize (permissionless)

Callable when `block.timestamp >= seasonEnd[seasonId]` and not yet finalized:

1. For each `tokenId` from `1` to `totalMinted()`:
   - If vault **eligible**: `satoLocked > 0` AND `block.timestamp < lockEnd` (still locked at finalize time):
     - `snapshotOwner[seasonId][tokenId] = ownerOf(tokenId)`
     - `totalWeight += weightAtMint[tokenId]`
2. `distributable[seasonId] = seasonPool[seasonId] + undistributedCarry`
3. If `totalWeight == 0`: move `distributable` to `undistributedCarry` for next season; mark finalized; **no claims**.
4. Else compute `claimAmount`; any remainder from wallet cap / rounding (`distributable - sum(claimAmount)`) is returned to `undistributedCarry`.
5. Mark `finalized[seasonId] = true`.

**Note:** Run finalize promptly after season end. Owners at finalize block are binding for claims. Last-hour transfer lock reduces sniping before boundary.

### Claim

```text
claimSeason(seasonId, tokenId):
  require finalized[seasonId]
  require msg.sender == snapshotOwner[seasonId][tokenId]
  require !claimed[seasonId][tokenId]
  raw = distributable[seasonId] × weightAtMint[tokenId] / totalWeight[seasonId]
```

**Per-wallet 10% cap** (same `seasonId`, same `msg.sender`):

```text
walletRaw = sum(raw for all tokenIds owned at claim time with same snapshotOwner == msg.sender)
walletCap = distributable[seasonId] × 1000 / 10_000
if walletRaw > walletCap:
  paid = raw × walletCap / walletRaw    // scale down each claim proportionally
else:
  paid = raw
```

Set `claimed[seasonId][tokenId] = true`; transfer the precomputed `claimAmount[seasonId][tokenId]` SATO.

Claims have no expiry. Remainder from wallet cap / rounding is carried at finalize time.

---

## 8. Lottery (prize fund)

| Parameter | Value |
|-----------|-------|
| Inflows | 15% of each `penaltySato` (SATO) |
| `prizeMinSato` | Immutable fixed SATO (no ETH oracle) |
| Draw | Permissionless when `prizeFund >= prizeMinSato`, interval elapsed, and **`pendingDrawPrize == 0`** |
| Tickets | `weightAtMint` among vaults with `satoLocked > 0` and `block.timestamp < lockEnd` at request-time draw snapshot |
| Randomness | Chainlink VRF v2.5 only on mainnet |
| Payout | `claimPrize()` pull pattern |
| Recovery | If VRF callback does not arrive before `lastPrizeDrawAt + PRIZE_DRAW_TIMEOUT`, anyone can call `recoverTimedOutPrizeDraw()` to move `pendingDrawPrize` back to `prizeFund` |

**VRF funding:** deployer funds Chainlink subscription at deploy; contract holds no admin to refill — document operational refill as **non-contract** ops (LINK top-up).

---

## 9. Secondary market

- Buyer inherits `lockEnd`, escrow, redeem/exit rights.
- **Pool claims** belong to `snapshotOwner` recorded at finalize, not necessarily current owner if NFT sold before finalize (price claim rights into sale).
- Rational floor ≈ `satoLocked × spot × (1 - expectedPenalty) + rarityPremium + pendingClaimValue`.

---

## 10. Smart contract surface

```text
SatoStonesVault.sol
  mint(grossAmount, lockDays)     // enum lockDays; qty=1
  earlyExit(tokenId)              // burns NFT
  redeem(tokenId)
  finalizeSeason(seasonId)
  claimSeason(seasonId, tokenId)
  requestPrizeDraw() / rawFulfillRandomWords / recoverTimedOutPrizeDraw() / claimPrize()
  withdrawDev()                   // to immutable devAddress
  previewMint(), maxGrossForMint(), getEarlyExitPenalty()

Mappings:
  vault[tokenId]: peakSato, satoLocked, lockDays, lockEnd, weightAtMint,
                  isGenesis, genesisRank, rarityTier
  seasonPool, distributable, totalWeight, snapshotOwner, claimed, finalized
  genesisMinted, undistributedCarry, devBalance, prizeFund, pendingDrawPrize, pendingDrawRequestId
```

**SATO:** `0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09` (immutable).

---

## 11. Risks and mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Transfer gaming before finalize | Medium | 1h season transfer lockout; snapshotOwner at finalize |
| Snapshot owner ≠ fair | Medium | Public finalize bot; document timing |
| Coordinated early exit | Medium | 10% wallet claim cap; exit burns NFT (no weight) |
| Sybil / split NFTs | Medium | sqrt weight; max 10 mints/wallet |
| 2100 cap confusion after burn | High | Spec: burn does not reopen mint |
| Fee-on-transfer SATO | Medium | Balance-delta intake |
| Empty season pool | Low | Carryover to next season |
| Prize fund starvation | Medium | Fixed `prizeMinSato`; draws wait |
| Reentrancy | Critical | `ReentrancyGuard` + CEI |
| Genesis MEV race | Medium | Product: fair launch comms; max 10/wallet |

---

## 12. Legacy comparison

| Aspect | Legacy contract | Vault NFT v1.3 |
|--------|-----------------|----------------|
| Mint | Fixed tier → curve sell | Escrow lock, no curve |
| Genesis | First 21 by tier order | First 21 with gross ≥ 500 SATO |
| Community | ETH split | SATO pool + seasons |
| Dev | 10% ETH | 2% of penalty SATO |

---

## 13. Implementation checklist

- [ ] `totalMinted <= 2100` forever; early exit burn does not allow new mint
- [ ] Gross → fee 2% → `peakSato`; penalty on `peakSato`
- [ ] Balance-delta `transferFrom` intake
- [ ] `lockDays` enum only (15/30/60)
- [ ] `weightAtMint` immutable; pool/lottery use it
- [ ] Season transfer lockout last 1h
- [ ] `finalizeSeason` writes `snapshotOwner` + `totalWeight`
- [ ] `claimSeason`: `msg.sender == snapshotOwner`; 10% wallet scale
- [ ] Carryover when `totalWeight == 0`
- [ ] Genesis FIFO ≥500 SATO; `genesisRank` 1–21
- [ ] Penalty split 4800/3300/1500/200
- [ ] `prizeMinSato` fixed; VRF subscription documented
- [ ] Fuzz penalty tables vs §3
- [ ] Frontend vault UX (`sato-stones-frontend.md`)

---

## 14. Decision log

### v1.3 (audit fixes)

| # | Topic | Decision |
|---|--------|----------|
| 13 | Snapshot claim | `snapshotOwner` at `finalizeSeason`; claim only by snapshot owner |
| 14 | Supply cap | 2100 mints ever; burn on early exit |
| 15 | Escrow | 2% fee from gross; penalty on `peakSato` |
| 16 | Zero-weight season | Pool carryover |
| 17 | Wallet cap algorithm | Proportional scale to 10% |
| 18 | `prizeMinSato` | Fixed SATO, no oracle |
| 19 | Season sniping | 1h transfer lock before season end |
| 20 | `weightAtMint` | Stored at mint for snapshots |
| 21 | Early-exit penalty | Ceil partial remaining days, so exits in the final partial day still pay one-day penalty |
| 22 | Prize draw VRF | Chainlink VRF v2.5 request struct and `rawFulfillRandomWords`; callback uses request-time ticket snapshot |
| 23 | Prize draw recovery | Stuck VRF recovery uses `PRIZE_DRAW_TIMEOUT = 1 day`, independent from draw cadence |

### v1.2

| # | Topic | Decision |
|---|--------|----------|
| 11 | Genesis vs tokenId | Decoupled; ≥500 SATO FIFO |
| 12 | First minter 100–499 | Allowed, not Genesis |

### v1.1

Weight sqrt, progressive penalty, no admin, 15d seasons, dev 2% of penalty.
