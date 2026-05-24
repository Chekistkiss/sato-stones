# Sato Stones — Vault NFT Specification

> **Version:** 2.0
> **Status:** Ready for implementation — supersedes v1.3 (`sato-stones-vault-nft.md`, kept as historical reference only).
> **Chain:** Ethereum Mainnet (EVM); L2 deployment optional in Phase 5.
> **SATO token:** `0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09` (immutable in production).

---

## 0. What changed from v1.3 and why

v1.3 was a working prototype with a fundamental product flaw: the team only earned money when users misbehaved (early-exit penalty 2% → dev), and user expected APY was ~3.6% — uncompetitive with mainstream DeFi. v2.0 is a structural rewrite of the economics with the same trustless, immutable, no-admin philosophy.

| Axis | v1.3 | v2.0 | Why |
|------|------|------|-----|
| Mint fee | 2% → pool only | **4%**, split 50% pool / 35% dev / 10% prize / 5% burn | Real recurring revenue to team |
| Lock periods | 15 / 30 / 60d | **30 / 90 / 180 / 365d** | True loyalty programme |
| Lock multipliers | 1.0 / 1.8 / 3.0× | **1.0 / 2.5 / 5.0 / 10.0×** | Reward long-term commitment |
| Min gross | 100 SATO | **50 SATO** | Lower retail barrier; activates Common tier |
| Max gross | min(10k, 0.1% supply) | **min(50k, 0.5% supply)** | Whale-friendly |
| Season duration | 15d | **30d** | Aligned with min lock; reduces gaming |
| Transfer lockout | 1h before seasonEnd | **24h before seasonEnd** | Closes wallet-cap split bypass |
| Wallet cap (pool claim) | 10%, by snapshotOwner | **8%, by `originalMinter`** | Truly closes sybil-split |
| Snapshot owner | `ownerOf` at finalize | **Accumulator hook** (last `to` of any transfer in season; else current owner) | Forgotten-season safety |
| Pool share | weight (static at mint) | **weight × time-in-season** | Removes late-mint dilution |
| Penalty split | 48/33/15/2 (pool/burn/prize/dev) | **65/5/20/10** (pool/burn/prize/dev) | More to lockers, dev sustainable |
| Penalty floor | none (rounds to zero in last <24h) | **5% of base** while locked | Removes free-exit cheat |
| Lottery winners | 1 (winner-take-all) | **3 winners (50/30/20%)** | Distributed wins |
| Lottery wallet cap | none | **15% by `originalMinter`** | Anti-whale monopoly |
| Genesis selection | first 21 to mint ≥500 SATO | **Top 21 by `genesisScore` in first 30 days** | Anti-MEV; rewards real commitment |
| Genesis multiplier | 1.2× | **1.5×**, active only while `satoLocked > 0` | Worth competing for, retains utility |
| Genesis early-exit | allowed | **forbidden** | Prevents flip-empty-frame abuse |
| Genesis re-pledge | not allowed | **allowed** after `redeem` (mint-fee paid again) | Lets Genesis stay productive |
| Royalty (EIP-2981) | none | **5%**, 40% pool / 40% dev / 20% Genesis pool | Recurring revenue + Genesis utility |
| Sponsored seasons | none | **`sponsorSeason()` ABI** | New marketing/revenue channel |
| Solvency helper | none | **`accountingLiabilities()` view** | Monitorable invariants |

---

## 1. Overview

Sato Stones is a **loyalty NFT vault** for SATO holders. Each NFT represents an escrowed SATO position: the holder locks SATO for a chosen period (30 / 90 / 180 / 365 days), receives a Vault NFT whose rarity reflects their commitment, and earns a share of recurring SATO inflows (mint fees, early-exit penalties, EIP-2981 royalties, sponsored deposits) proportional to **weight × time-in-pool**.

Hard product framing: this is **not a yield farm**. It is **long-term holder rewards**. Users who lock and hold earn from users who break commitments and from secondary-market activity.

### 1.1. Lifecycle

```
MINT  →  ACTIVE LOCK  →  (earlyExit  |  redeem)  →  (Genesis: repledge)
```

- `mint` → pull SATO, pay 4% fee, escrow `peakSato`, mint ERC-721A.
- `redeem` (after `lockEnd`) → return 100% of `satoLocked`; NFT stays as a permanent record. For Genesis: also unlocks `repledge`.
- `earlyExit` (before `lockEnd`) → progressive penalty (5% floor); **burns NFT** for non-Genesis; **forbidden for Genesis**.

### 1.2. Supply

- **Max supply: 2100** mints ever. Burns from `earlyExit` do not free slots.
- Of these, **up to 21 are Genesis**, selected at day 30 from the leaderboard (§5).
- Token IDs are sequential `#1 … #2100` independent of Genesis status.

---

## 2. Canonical parameters (immutable)

All BPS, caps, addresses, and durations below are **immutable** in the constructor. No admin keys. No upgrade proxy. No pause.

### 2.1. Supply and limits

| Parameter | Value | Constant name |
|-----------|-------|---------------|
| `MAX_SUPPLY` | 2100 | `MAX_SUPPLY` |
| `MAX_GENESIS` | 21 | `MAX_GENESIS` |
| `MAX_MINTS_PER_WALLET` (lifetime) | 5 | `MAX_MINTS_PER_WALLET` |
| `MIN_GROSS` | 50 SATO | `MIN_GROSS` |
| `MAX_GROSS_CAP` (hard) | 50 000 SATO | `MAX_GROSS_CAP` |
| `MAX_GROSS_BPS_OF_SUPPLY` | 50 bps (0.5%) | `MAX_GROSS_BPS_OF_SUPPLY` |
| Min `peakSato` for bootstrap | 25 SATO (gross 26.05) | derived |

`maxGrossForMint() = min(MAX_GROSS_CAP, sato.totalSupply() × MAX_GROSS_BPS_OF_SUPPLY / 10_000)`.

If `maxGrossForMint() < MIN_GROSS`, **the contract is dead until SATO supply grows**. This must be checked at deploy time (precondition: `sato.totalSupply() ≥ 1_000_000 SATO`).

### 2.2. Mint fee (4% of gross)

```
MINT_FEE_BPS              = 400   // 4% of gross
MINT_FEE_POOL_BPS         = 5000  // 50% of fee  → seasonPool
MINT_FEE_DEV_BPS          = 3500  // 35% of fee  → devBalance
MINT_FEE_PRIZE_BPS        = 1000  // 10% of fee  → prizeFund
MINT_FEE_BURN_BPS         = 500   //  5% of fee  → DEAD
peakSato = gross × (10_000 − MINT_FEE_BPS) / 10_000   // = gross × 96%
```

Splits inside the fee must sum to exactly 10 000 bps; rounding dust (≤4 wei) goes to `seasonPool`.

### 2.3. Lock periods

| Lock | `lockDays` enum | Seconds | Multiplier (bps) | Base penalty (bps) |
|------|-----------------|---------|------------------|--------------------|
| 30d  | `Thirty`        | `30 days`  | `10_000` (1.0×) | `3500` (35%) |
| 90d  | `Ninety`        | `90 days`  | `25_000` (2.5×) | `2500` (25%) |
| 180d | `OneEighty`     | `180 days` | `50_000` (5.0×) | `2000` (20%) |
| 365d | `ThreeSixtyFive`| `365 days` | `100_000` (10.0×) | `1500` (15%) |

Other values revert `InvalidLockDays`.

### 2.4. Weight and rarity

```
weightAtMint = sqrt(peakSato) × lockMultiplierBps × genesisMultiplierBps / (WEIGHT_SCALE × 10_000 × 10_000)
WEIGHT_SCALE = 1e9
GENESIS_MULTIPLIER_BPS = 15_000   // 1.5× (only applied while satoLocked > 0)
NON_GENESIS_BPS        = 10_000   // 1.0×
```

`weightAtMint` is stored as `uint32` (cap-protected; max conceivable weight at 50k SATO × 10× × 1.5× ≈ 3 350; fits easily).

**Rarity tiers** (`_rarityFromWeight`):

| Range | Tier | Visual |
|-------|------|--------|
| 0 – 24   | Common   | Grey  |
| 25 – 79  | Uncommon | Blue  |
| 80 – 249 | Rare     | Purple|
| 250+     | Mythic   | Gold  |

A 50-SATO 30d mint yields `sqrt(48e18)/1e9 ≈ 22` → **Common** (achievable). A 500-SATO 90d → `sqrt(480e18)/1e9 × 2.5 ≈ 173` → **Rare**. A 5 000-SATO 365d → ~707 → **Mythic**.

### 2.5. Early-exit penalty

```
require(block.timestamp < lockEnd)                     // else redeem()
require(!vaults[id].isGenesis)                         // Genesis cannot earlyExit
daysRemaining = ceilDiv(lockEnd − block.timestamp, 1 days)
penaltyBps   = max(
    PENALTY_FLOOR_BPS,                                 // 500 (5%)
    basePenaltyBps[lockDays] × daysRemaining / lockDays
)
penaltySato  = peakSato × penaltyBps / 10_000
userReceives = satoLocked − penaltySato
```

`PENALTY_FLOOR_BPS = 500` ensures no free exit in the last partial day, regardless of lock length.

### 2.6. Penalty split (of `penaltySato`)

```
PENALTY_POOL_BPS  = 6500   // 65% → seasonPool[seasonAtExit]
PENALTY_PRIZE_BPS = 2000   // 20% → prizeFund
PENALTY_DEV_BPS   = 1000   // 10% → devBalance
PENALTY_BURN_BPS  =  500   //  5% → DEAD
```

Sum is exactly 10 000 bps. Any rounding dust (≤3 wei) goes to `seasonPool`.

### 2.7. Seasons

```
SEASON_DURATION       = 30 days
TRANSFER_LOCKOUT      = 24 hours        // before each seasonEnd; reverts non-mint/burn transfers
WALLET_CAP_BPS        = 800             // 8% of distributable per originalMinter
FINALIZE_GRACE_PERIOD = 14 days         // see §4.4 "forgotten season safety"
```

### 2.8. Lottery

```
prizeMinSato            : immutable, configured at deploy (recommend 50_000 ether)
prizeDrawInterval       : immutable (recommend 30 days)
PRIZE_DRAW_TIMEOUT      = 1 day
LOTTERY_WALLET_CAP_BPS  = 1500   // 15% of total snapshot weight per originalMinter
PRIZE_FIRST_BPS         = 5000
PRIZE_SECOND_BPS        = 3000
PRIZE_THIRD_BPS         = 2000
```

VRF integration: **Chainlink VRF v2.5 only**, via `VRFConsumerBaseV2Plus`. The contract MUST inherit the official base and implement `_fulfillRandomWords(uint256, uint256[])`, not expose a public `fulfillRandomWords`. Subscription is funded off-protocol.

### 2.9. Genesis race

```
GENESIS_RACE_DURATION    = 30 days
GENESIS_MIN_SCORE        = 4_500e18 // = 500 SATO × 9 (≈ 500 gross, 90d-equivalent threshold)
GENESIS_PEAK_FLOOR       = 200 ether // min peakSato to be a candidate
```

`genesisScore` is computed during the race (§5).

### 2.10. Royalty (EIP-2981)

```
ROYALTY_BPS         = 500    // 5% of secondary sale price
ROYALTY_POOL_BPS    = 4000   // 40% → seasonPool
ROYALTY_DEV_BPS     = 4000   // 40% → devBalance
ROYALTY_GENESIS_BPS = 2000   // 20% → genesisPool (split equally among active Genesis at distribute time)
```

Royalty is paid in **SATO** (paid-in-kind requirement; the contract accepts whatever SATO arrives via direct transfer or marketplace router; see §10). Any SATO balance not accounted for by liabilities is treated as royalty income and split via `distributeRoyalty()`.

### 2.11. Addresses

- `DEAD = 0x000000000000000000000000000000000000dEaD`
- `devAddress` — immutable, set at deploy. Recommended: multisig.

---

## 3. Mint mechanics

### 3.1. Function signature

```solidity
function mint(uint256 grossAmount, LockDays lockDays)
    external
    nonReentrant
    returns (uint256 tokenId);
```

### 3.2. Algorithm

1. **Preconditions**
   - `totalMintedEver < MAX_SUPPLY` else `MintedOut()`.
   - `walletMintCount[msg.sender] < MAX_MINTS_PER_WALLET` else `ExceedsWalletMintLimit()`.
   - `grossAmount >= MIN_GROSS` else `DepositTooLow()`.
   - `grossAmount <= maxGrossForMint()` else `DepositTooHigh()`.
   - `lockDays ∈ {Thirty, Ninety, OneEighty, ThreeSixtyFive}` else `InvalidLockDays()`.

2. **Fee-on-transfer-safe intake**
   ```
   balanceBefore = sato.balanceOf(address(this))
   sato.safeTransferFrom(msg.sender, address(this), grossAmount)
   received = sato.balanceOf(address(this)) - balanceBefore
   require(received >= grossAmount × 9600 / 10_000)        // tolerate small fees
   ```
   All math below uses `received`, not `grossAmount`.

3. **Fee split** (`mintFee = received × MINT_FEE_BPS / 10_000`)
   - `pool = mintFee × MINT_FEE_POOL_BPS / 10_000`
   - `dev  = mintFee × MINT_FEE_DEV_BPS  / 10_000`
   - `prize = mintFee × MINT_FEE_PRIZE_BPS / 10_000`
   - `burn = mintFee × MINT_FEE_BURN_BPS / 10_000`
   - `dust = mintFee − pool − dev − prize − burn` → `seasonPool[currentSeason]`
   - `peakSato = received − mintFee`
   - Apply: `seasonPool[currentSeason] += pool + dust`; `devBalance += dev`; `prizeFund += prize`; `sato.safeTransfer(DEAD, burn)`.

4. **Vault state**
   - `mintTime = block.timestamp`
   - `lockEnd = mintTime + lockSeconds(lockDays)`
   - `weight = computeWeight(peakSato, lockDays, isGenesis=false)`  // Genesis multiplier applied later if/when Genesis confirmed (see §5.6)
   - `rarity = rarityFromWeight(weight)`

5. **Mint NFT**
   - `tokenId = _nextTokenId()` (ERC721A `_startTokenId() = 1`)
   - `_mint(msg.sender, 1)`
   - Store full `Vault` struct (see §10.1).
   - Set `originalMinter[tokenId] = msg.sender`.
   - `walletMintCount[msg.sender]++`; `totalMintedEver++`.

6. **Genesis race update** (§5)
   - If `block.timestamp < t0 + GENESIS_RACE_DURATION`:
     - Compute `genesisScore = peakSato × lockMultiplierBps / 10_000`.
     - If `genesisScore >= GENESIS_MIN_SCORE` and `peakSato >= GENESIS_PEAK_FLOOR`: call `_offerGenesisCandidate(tokenId, genesisScore)`.

7. **Auto-finalize Genesis race** if not yet done and `block.timestamp >= t0 + GENESIS_RACE_DURATION`:
   - Inline call `_finalizeGenesisIfDue()`.

8. **Emit event** `StoneMinted(...)`.

### 3.3. `previewMint`

```solidity
function previewMint(uint256 grossAmount, LockDays lockDays)
    external view returns (
        uint256 peakSato,
        uint32 weightWithoutGenesis,
        uint32 weightIfGenesis,
        RarityTier rarityWithoutGenesis,
        RarityTier rarityIfGenesis,
        uint256 estGenesisScore,
        bool genesisRaceOpen
    );
```

UI must show **both** non-Genesis and Genesis weights/tiers; users must understand Genesis is only finalized at day 30 and is not guaranteed.

---

## 4. Seasons and community pool

### 4.1. Timing

```
seasonId(t)        = (t − t0) / SEASON_DURATION
seasonStart(s)     = t0 + s × SEASON_DURATION
seasonEnd(s)       = t0 + (s + 1) × SEASON_DURATION
currentSeasonId()  = seasonId(block.timestamp)
```

### 4.2. Pool inflows

| Source | Credited to | Trigger |
|--------|-------------|---------|
| 50% of mint fee (= 2% of gross) | `seasonPool[seasonId at mint]` | `mint()` |
| 65% of `penaltySato` | `seasonPool[seasonId at exit]` | `earlyExit()` |
| 40% of royalty SATO | `seasonPool[seasonId at distribute]` | `distributeRoyalty()` |
| `sponsorSeason()` deposits | `seasonPool[seasonId chosen by sponsor]` | `sponsorSeason()` |

`undistributedCarry` collects: (a) seasons with `totalEffectiveWeight == 0` and (b) wallet-cap / rounding remainders from finalize.

### 4.3. Time-weighted effective weight

For each stone `i` and season `s`:

```
mintTime_i        = vaults[i].mintTime
lockEnd_i         = vaults[i].lockEnd
seasonStart_s     = t0 + s × SEASON_DURATION
seasonEnd_s       = t0 + (s + 1) × SEASON_DURATION

activeStart       = max(seasonStart_s, mintTime_i)
activeEnd         = min(seasonEnd_s, lockEnd_i)
secondsActive     = activeEnd > activeStart ? activeEnd - activeStart : 0

effectiveWeight_i_s = weightAtMint_i × secondsActive / SEASON_DURATION
```

Additionally, only eligible stones contribute: `vaults[i].satoLocked > 0` at `seasonEnd_s` (i.e., not redeemed during the season).

For stones fully active across the season, `effectiveWeight = weightAtMint`. For mint-season or last-lock-season, it is fractional.

### 4.4. Transfer lockout and snapshot accumulator

```
_beforeTokenTransfers(from, to, startTokenId, quantity):
    if (from == address(0) || to == address(0)) return       // mint / burn always allowed
    s = currentSeasonId()
    end = seasonEnd(s)
    if (block.timestamp >= end − TRANSFER_LOCKOUT && block.timestamp < end) revert SeasonTransferLocked()
    for (i = 0; i < quantity; i++):
        seasonEndOwner[s][startTokenId + i] = to
```

At finalize time, the binding owner for tokenId is `seasonEndOwner[s][tokenId]` if set, else `ownerOf(tokenId)`. This guarantees:

- Snapshot is the **last owner during the season** (or current owner if no transfers happened).
- No way to bypass via transfer in the last 24 hours.
- No way to game forgotten seasons by transferring after the season — the accumulator only writes inside `s`.

### 4.5. Finalize (permissionless)

```solidity
function finalizeSeason(uint256 seasonId) external nonReentrant;
```

Preconditions:
- `block.timestamp >= seasonEnd(seasonId)` else `SeasonNotEnded()`.
- `block.timestamp <= seasonEnd(seasonId) + FINALIZE_GRACE_PERIOD` else `FinalizeWindowExpired()` (carry to next finalized season; see §4.7).
- `!seasonFinalized[seasonId]` else `SeasonAlreadyFinalized()`.

Algorithm:

1. `distributable = seasonPool[seasonId] + undistributedCarry`
2. Zero `seasonPool[seasonId]` and `undistributedCarry`.
3. Single pass over tokenIds `1 … totalMintedEver`:
   - Skip if `!_exists(id)`.
   - Compute `effectiveWeight_id` per §4.3. Skip if zero.
   - `snapshotOwner[seasonId][id] = seasonEndOwner[seasonId][id] != address(0) ? seasonEndOwner[seasonId][id] : ownerOf(id)`.
   - `weightInSeason[seasonId][id] = effectiveWeight_id`.
   - `totalEffectiveWeight += effectiveWeight_id`.
   - Aggregate by `originalMinter[id]` into a temporary `minterRaw[originalMinter[id]] += effectiveWeight_id × distributable / N` (placeholder; see §4.6 — actual cap algorithm below).
4. If `totalEffectiveWeight == 0`:
   - `undistributedCarry = distributable`; mark finalized; emit `SeasonFinalized(seasonId, 0, 0)`; return.
5. Apply wallet cap (§4.6) and write `claimAmount[seasonId][id]`.
6. Any remainder (rounding + cap-clipped) → `undistributedCarry`.
7. `seasonFinalized[seasonId] = true`; emit `SeasonFinalized(seasonId, distributable, totalEffectiveWeight)`.

**Gas note:** This single pass is O(N) where N = `totalMintedEver` ≤ 2100. For 2100 stones, gas is bounded but tight. Implementation MUST be benchmarked; if it exceeds 12M gas, **switch to paginated finalize** (`finalizeSeasonChunk(seasonId, startId, endId)` + `finalizeSeasonClose(seasonId)`). Default implementation MUST include both single-call and paginated entry points.

### 4.6. Wallet cap by `originalMinter`

```
walletCap = distributable × WALLET_CAP_BPS / 10_000

For each originalMinter M with aggregate raw share R_M:
    if (R_M <= walletCap):
        scale_M = 1
    else:
        scale_M = walletCap / R_M

For each tokenId id with snapshotOwner != address(0):
    rawId = distributable × weightInSeason[seasonId][id] / totalEffectiveWeight
    claimAmount[seasonId][id] = rawId × scale_M{originalMinter[id]}
```

Aggregation uses a memory map (or single linear scan, see implementation note in §10). Total `claimAmount` ≤ `distributable`; difference goes to `undistributedCarry`.

**Why `originalMinter` and not `snapshotOwner`:** the only sybil-resistant identity we can enforce is the wallet that paid the mint fee. Transfers to fresh wallets do not bypass the cap. Buyers on secondary still receive the payout (they own the NFT at season end), but the cap aggregation is against the original minter's "family".

If a stone changes hands frequently across many wallets (5+ unique non-minter holders during its lifetime), `originalMinter` resets to the current holder via `unbindMinter(tokenId)` — opt-in by current owner, but only callable if the chain of transfers is ≥5 unique addresses. Stretch goal; can ship v2.0 without this and add later.

### 4.7. Forgotten season safety

If a season is not finalized within `FINALIZE_GRACE_PERIOD` (14 days after `seasonEnd`), its `distributable` is moved to `undistributedCarry` at the next finalize, and **no claims** are paid for that season. Anyone can call `closeMissedSeason(seasonId)` after the grace period to do this explicitly.

This prevents the abuse where stale seasons can be finalized arbitrarily later with manipulated `ownerOf`.

### 4.8. Claim

```solidity
function claimSeason(uint256 seasonId, uint256 tokenId) external nonReentrant;
```

- `seasonFinalized[seasonId]` else `SeasonNotFinalized()`.
- `snapshotOwner[seasonId][tokenId] == msg.sender` else `NotSnapshotOwner()`.
- `!seasonClaimed[seasonId][tokenId]` else `AlreadyClaimed()`.
- `claimAmount[seasonId][tokenId] > 0` else `NothingToClaim()`.

Marks claimed, transfers SATO, emits `SeasonClaimed`. Claims have no expiry.

A batch helper `claimSeasonBatch(uint256 seasonId, uint256[] calldata tokenIds)` is provided for UX.

---

## 5. Genesis (top-21 leaderboard)

### 5.1. Rationale

Genesis is the marquee status: 21 founder-tier NFTs with permanent prestige, ongoing royalty income, lottery boost, and the right to repledge after redeem. To prevent MEV sniping (the v1.3 fatal flaw), Genesis is **earned by commitment** in the first 30 days, not first-come-first-served.

### 5.2. Eligibility (during the race)

A mint is a Genesis candidate iff all of:
- `block.timestamp < t0 + GENESIS_RACE_DURATION` (within 30-day race)
- `peakSato >= GENESIS_PEAK_FLOOR` (≥200 SATO peak)
- `genesisScore >= GENESIS_MIN_SCORE` (≥4 500 e18)

```
genesisScore = peakSato × lockMultiplierBps / 10_000
```

This means a 500 SATO 90d (score 1250 × 2.5 = 1 200 effectively) misses; the floor 4 500 requires e.g. 500 SATO × 9 = 1 500 × 365d's 10× → 5 000 score, or 1 800 SATO × 2.5× = 4 500. Designed to require meaningful commitment.

### 5.3. Candidate list maintenance

A storage array `genesisCandidates[21]` holds `(tokenId, genesisScore)` sorted descending by score. The lowest slot is `genesisCandidates[20]`.

```
function _offerGenesisCandidate(uint256 tokenId, uint256 score) internal:
    if (genesisCandidatesCount < MAX_GENESIS):
        insert in sorted position
    else if (score > genesisCandidates[MAX_GENESIS - 1].score):
        evict slot 20; insert in sorted position
    emit GenesisCandidateUpdated(tokenId, score, newRank)
```

Linear insertion of 21 entries on each qualifying mint is ≤21 storage writes. Worst case ≈ 100k gas. Acceptable.

### 5.4. Race finalization

```solidity
function finalizeGenesis() external;
```

- Callable by anyone after `block.timestamp >= t0 + GENESIS_RACE_DURATION`.
- Idempotent: if `genesisFinalized` is already true, revert `GenesisAlreadyFinalized()`.
- Iterates `genesisCandidates`, sets `vaults[id].isGenesis = true`, `vaults[id].genesisRank = rank+1` (1..21), `vaults[id].weightAtMint = computeWeight(peakSato, lockDays, isGenesis=true)`.
- Sets `genesisFinalizedAt = block.timestamp`, `genesisFinalized = true`.
- Emits `GenesisAssigned(tokenId, rank, owner)` for each.

Also called inline from `mint()` if race expired and not yet finalized (cheap if no candidates change).

If fewer than 21 candidates qualify in the race window, the unfilled Genesis slots **remain unfilled forever**. The collection has `n ≤ 21` Genesis where `n` is the number of qualifying minters in the first 30 days.

### 5.5. Genesis benefits

While Genesis is **active** (`isGenesis == true && satoLocked > 0`):

1. **Weight multiplier 1.5×** in season pool and lottery (applied at finalize-genesis time by recomputing `weightAtMint`).
2. **Royalty share:** 20% of every royalty distribution is split equally among the set of currently-active Genesis (snapshot at distribute call).
3. **Lottery tickets aggregated by `originalMinter`** as usual, but Genesis weights count at their boosted 1.5× level.
4. **No `earlyExit`** allowed: `earlyExit(tokenId)` reverts `GenesisCannotExit()`.
5. **`repledge` available after `redeem`** (§5.6).

When Genesis is **dormant** (`satoLocked == 0`):
- Cosmetic Genesis frame in metadata is preserved (collector value).
- No royalty share, no weight, no lottery tickets.
- Can be revived via `repledge`.

### 5.6. `repledge` (Genesis only, post-redeem)

```solidity
function repledge(uint256 tokenId, uint256 grossAmount, LockDays lockDays)
    external nonReentrant;
```

Preconditions:
- `ownerOf(tokenId) == msg.sender`.
- `vaults[tokenId].isGenesis == true`.
- `vaults[tokenId].satoLocked == 0` and `vaults[tokenId].redeemed == true`.
- `grossAmount` within current `[MIN_GROSS, maxGrossForMint()]`.
- `lockDays ∈ {Thirty, Ninety, OneEighty, ThreeSixtyFive}`.

Algorithm: identical to `mint()` body **except**:
- No new NFT is created; existing `tokenId` is reused.
- `walletMintCount[msg.sender]` is NOT incremented.
- `totalMintedEver` is NOT incremented.
- `genesisRank` is preserved.
- `peakSato`, `satoLocked`, `lockEnd`, `mintTime`, `weightAtMint`, `rarity`, `redeemed = false` are updated to reflect the new lock.
- The 4% mint fee is paid again, split identically.

Emits `Repledged(tokenId, owner, grossAmount, lockDays)`.

### 5.7. Genesis royalty pool

A separate accumulator `genesisRoyaltyPool` collects the 20% of each royalty distribution. On `claimGenesisRoyalty()`, an active Genesis holder claims their pro-rata share of the **current** pool divided equally among currently-active Genesis. This is checkpointed per (holder, distribution index) — see §10 for details.

---

## 6. Lottery (Chainlink VRF v2.5)

### 6.1. Inflows

- 10% of each mint fee (= 0.4% of gross).
- 20% of each `penaltySato`.
- Direct SATO donations are NOT routed to prize — they go to `distributeRoyalty()`.

### 6.2. Request

```solidity
function requestPrizeDraw() external nonReentrant returns (uint256 requestId);
```

Permissionless. Reverts unless:
- No pending draw (`pendingDrawRequestId == 0 && pendingDrawPrize == 0`).
- `address(vrfCoordinator) != address(0)` (else `LotteryDisabled()`).
- `prizeFund >= prizeMinSato` (`PrizePoolTooLow`).
- `block.timestamp >= lastPrizeDrawAt + prizeDrawInterval` (`PrizeDrawTooSoon`).
- At least 1 eligible ticket exists at request time (`NoEligibleTickets`).

Algorithm:
1. Snapshot eligible tickets: for each `id ∈ [1, totalMintedEver]` with `vaults[id].satoLocked > 0 && block.timestamp < vaults[id].lockEnd`:
   - Aggregate weight by `originalMinter[id]` into a memory map (with Genesis 1.5× boost already baked into `weightAtMint`).
2. Apply per-minter cap of 15% of total snapshot weight (`LOTTERY_WALLET_CAP_BPS`).
3. Persist the capped per-minter weight list and total: `_drawMinters[]`, `_drawMinterCumulativeWeights[]`, `pendingDrawTotalWeight`.
4. `pendingDrawPrize = prizeFund; prizeFund = 0;`
5. `lastPrizeDrawAt = block.timestamp;`
6. Call VRF: `vrfCoordinator.requestRandomWords(... numWords = 3 ...)`.
7. Store `pendingDrawRequestId`. Emit `PrizeRequested`.

### 6.3. Fulfillment

```solidity
function _fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override;
```

Inherits `VRFConsumerBaseV2Plus`. The base routes `rawFulfillRandomWords` from the coordinator into this internal override.

Algorithm:
1. Validate `requestId == pendingDrawRequestId` else `InvalidDrawRequest`.
2. `amount = pendingDrawPrize; pendingDrawPrize = 0;`
3. If snapshot empty (defensive): return `amount` to `prizeFund`, clear pending state, return.
4. Draw winner 1: `roll1 = randomWords[0] % pendingDrawTotalWeight`; binary search `_drawMinterCumulativeWeights` → `winnerMinter1`.
5. Mark `winnerMinter1`'s weight as zero; rebuild cumulative; if total > 0, draw winner 2 with `roll2 = randomWords[1] % newTotal`.
6. Repeat for winner 3 if remaining minters > 0.
7. Allocate:
   - `pendingPrize[winnerMinter1] += amount × PRIZE_FIRST_BPS  / 10_000`
   - `pendingPrize[winnerMinter2] += amount × PRIZE_SECOND_BPS / 10_000`
   - `pendingPrize[winnerMinter3] += amount × PRIZE_THIRD_BPS  / 10_000`
   - Any rounding dust → `prizeFund`.
   - If <3 distinct minters, undistributed shares → `prizeFund`.
8. Emit `PrizeAssigned(drawId, winner, place, amount)` for each.
9. Clear pending state.

### 6.4. Claim

```solidity
function claimPrize() external nonReentrant;
```

Pull pattern; pays `pendingPrize[msg.sender]`, zeros, transfers SATO.

### 6.5. Recovery

```solidity
function recoverTimedOutPrizeDraw() external nonReentrant;
```

If `pendingDrawRequestId != 0 && block.timestamp >= lastPrizeDrawAt + PRIZE_DRAW_TIMEOUT`, returns `pendingDrawPrize` to `prizeFund`, clears all draw state. Subsequent late VRF callback for the recovered request reverts (requestId mismatch).

### 6.6. Callback gas

`vrfCallbackGasLimit` set at deploy to **750 000** (vs v1.3's 250k). With per-minter aggregation (much smaller than per-token), top-3 distribution, and binary search over ≤2 100 minters, this is sufficient with significant headroom. Implementation MUST gas-benchmark at 2 100 stones with 2 100 unique minters as worst case.

---

## 7. Royalty (EIP-2981) and `distributeRoyalty`

### 7.1. EIP-2981 interface

```solidity
function royaltyInfo(uint256 /*tokenId*/, uint256 salePrice)
    external view returns (address receiver, uint256 royaltyAmount)
{
    return (address(this), salePrice * ROYALTY_BPS / 10_000);
}
```

`supportsInterface(0x2a55205a)` returns true.

### 7.2. Royalty token

Royalty MUST be paid in SATO. Marketplaces that pay royalties in ETH or other tokens (most do, by default) are out of scope; that royalty is forfeit. The team must document this clearly and target SATO-aware marketplaces. The Sato Stones companion site MAY display a "voluntary royalty" widget letting traders top up SATO into the contract post-trade.

### 7.3. `distributeRoyalty`

```solidity
function distributeRoyalty() external nonReentrant;
```

Permissionless. Computes:

```
liabilities = sumLocked + sumSeasonPools + undistributedCarry + devBalance + prizeFund
             + pendingDrawPrize + sumPendingPrizes + sumUnclaimedSeasonClaims
             + genesisRoyaltyPool + sumPendingGenesisClaims
balance = sato.balanceOf(address(this))
royaltyIn = balance - liabilities  // (must be >= 0; else revert NoRoyaltyToDistribute)
```

Splits `royaltyIn`:
- `royaltyIn × ROYALTY_POOL_BPS    / 10_000` → `seasonPool[currentSeasonId()]`
- `royaltyIn × ROYALTY_DEV_BPS     / 10_000` → `devBalance`
- `royaltyIn × ROYALTY_GENESIS_BPS / 10_000` → `genesisRoyaltyPool` (and triggers a new distribution checkpoint, see §10)
- Dust → `seasonPool`.

Emits `RoyaltyDistributed(royaltyIn, poolAmount, devAmount, genesisAmount)`.

The view `accountingLiabilities()` returns `liabilities` for monitoring; on-chain solvency tests are mandatory (§12).

### 7.4. Genesis royalty claim

`genesisRoyaltyPool` accumulates SATO. Each distribution emits an indexed checkpoint with `(checkpointIndex, amountAdded, activeGenesisSet)`. A holder of an active Genesis can call:

```solidity
function claimGenesisRoyalty(uint256 tokenId, uint256[] calldata checkpointIndices) external nonReentrant;
```

For each unclaimed checkpoint where `tokenId` was active at the time of distribution, pay `checkpoint.amountAdded / checkpoint.activeGenesisCount` SATO from `genesisRoyaltyPool`.

Simpler alternative if checkpoint complexity is too high: a "current pot, equal split among current-active Genesis" model with `lastClaimedAt` tracking. The spec authoritatively uses **checkpoint model** to avoid free-rider gaming. Implementation may simplify if gas-prohibitive, with explicit decision in the decision log.

---

## 8. Sponsored seasons

```solidity
function sponsorSeason(uint256 seasonId, uint256 amount, string calldata memo)
    external nonReentrant;
```

- `seasonId >= currentSeasonId()` (cannot sponsor finalized past seasons) else `SeasonAlreadyFinalized()` (or `InvalidSeason`).
- `amount > 0` else `ZeroAmount`.
- Transfer `amount` SATO from caller (fee-on-transfer safe).
- 10% goes to `devBalance` (project margin on sponsorship).
- 90% credited to `seasonPool[seasonId]`.
- Emit `SeasonSponsored(seasonId, sponsor, gross, netToPool, memo)`.

UI surfaces sponsored seasons prominently. The 10% spread is the project's marketing-channel revenue.

---

## 9. Lifecycle summary

| Step | Function | Effects |
|------|----------|---------|
| Mint | `mint(gross, lock)` | Pulls SATO, splits 4% fee, escrows peakSato, mints NFT, updates Genesis race |
| Active lock | (none) | `satoLocked == peakSato`; eligible for time-weighted season share and lottery |
| Early exit | `earlyExit(tokenId)` | Progressive penalty (5% floor), splits 65/5/20/10, **burns NFT** (revert if Genesis) |
| Redeem | `redeem(tokenId)` | After `lockEnd`: returns 100% `satoLocked`, NFT kept (dormant Genesis if applicable) |
| Repledge (Genesis) | `repledge(tokenId, gross, lock)` | After `redeem`: reactivates Genesis vault, pays 4% fee, new lock |
| Finalize season | `finalizeSeason(s)` or `finalizeSeasonChunk(...)` + `finalizeSeasonClose(...)` | Computes time-weighted snapshot, applies wallet cap, writes claim amounts |
| Close missed season | `closeMissedSeason(s)` | After grace period: distributable → carry |
| Claim season | `claimSeason(s, id)` or `claimSeasonBatch(s, ids[])` | Snapshot owner pulls claim amount |
| Request draw | `requestPrizeDraw()` | Snapshots minter-aggregated weights, calls VRF |
| Fulfill | `_fulfillRandomWords(...)` (Chainlink) | Top-3 winners by minter, allocates pendingPrize |
| Recover draw | `recoverTimedOutPrizeDraw()` | After 1d timeout: returns pending to prizeFund |
| Claim prize | `claimPrize()` | Pull pattern |
| Sponsor | `sponsorSeason(s, amount, memo)` | 90% to pool, 10% to dev |
| Distribute royalty | `distributeRoyalty()` | Permissionless; splits surplus SATO 40/40/20 |
| Claim genesis royalty | `claimGenesisRoyalty(id, idxs[])` | Pulls Genesis share |
| Withdraw dev | `withdrawDev()` | Sends `devBalance` to `devAddress` |
| Finalize Genesis race | `finalizeGenesis()` | At day 30: assigns top-21 |

---

## 10. Contract surface

### 10.1. Storage

```solidity
struct Vault {
    uint256 peakSato;       // escrowed amount at mint/repledge (after fee)
    uint256 satoLocked;     // current escrow (== peakSato until exit/redeem, then 0)
    uint64  mintTime;       // for time-weighted share
    uint64  lockEnd;
    uint32  weightAtMint;   // updated on Genesis finalize and repledge
    LockDays lockDays;
    RarityTier rarity;
    bool    isGenesis;
    uint8   genesisRank;    // 1..21 or 0
    bool    redeemed;
}

mapping(uint256 tokenId => Vault) public vaults;
mapping(uint256 tokenId => address) public originalMinter;     // immutable per token
mapping(address minter => uint256) public walletMintCount;

mapping(uint256 seasonId => uint256) public seasonPool;
uint256 public undistributedCarry;
mapping(uint256 seasonId => bool) public seasonFinalized;
mapping(uint256 seasonId => uint256) public seasonTotalEffectiveWeight;
mapping(uint256 seasonId => mapping(uint256 tokenId => address)) public seasonEndOwner;   // accumulator
mapping(uint256 seasonId => mapping(uint256 tokenId => address)) public snapshotOwner;    // finalized
mapping(uint256 seasonId => mapping(uint256 tokenId => uint256)) public claimAmount;
mapping(uint256 seasonId => mapping(uint256 tokenId => bool)) public seasonClaimed;
mapping(uint256 seasonId => mapping(uint256 tokenId => uint256)) public weightInSeason;   // optional, for transparency

uint256 public devBalance;
uint256 public prizeFund;
uint256 public pendingDrawPrize;
uint256 public pendingDrawRequestId;
uint256 public pendingDrawTotalWeight;
uint256 public lastPrizeDrawAt;
mapping(uint256 requestId => uint256 drawId) private _vrfRequestToDrawId;
mapping(address minter => uint256) public pendingPrize;
address[] private _drawMinters;
uint256[] private _drawMinterCumulativeWeights;

// Genesis race
struct GenesisCandidate { uint256 tokenId; uint256 score; }
GenesisCandidate[21] public genesisCandidates;
uint256 public genesisCandidatesCount;
bool public genesisFinalized;
uint64 public genesisFinalizedAt;
uint256 public genesisMintedCount;          // == final Genesis count (1..21)

// Genesis royalty
uint256 public genesisRoyaltyPool;
struct GenesisCheckpoint { uint256 amount; uint16 activeCount; uint64 timestamp; }
GenesisCheckpoint[] public genesisCheckpoints;
mapping(uint256 tokenId => mapping(uint256 checkpointIdx => bool)) public genesisCheckpointClaimed;

// Solvency
uint256 public sumLocked;                   // updated incrementally on mint/redeem/exit/repledge
uint256 public sumPendingSeasonClaims;      // optional aggregate for accountingLiabilities()
```

### 10.2. Events

```
StoneMinted(minter, tokenId, gross, peakSato, lockDays, weight, mintTime, lockEnd)
GenesisCandidateUpdated(tokenId, score, rank)
GenesisAssigned(tokenId, rank, owner)
EarlyExit(tokenId, owner, penaltySato, returnedSato)
Redeemed(tokenId, owner, satoReturned)
Repledged(tokenId, owner, grossAmount, lockDays, peakSato, weight)
SeasonFinalized(seasonId, distributable, totalEffectiveWeight)
SeasonClaimed(seasonId, tokenId, claimant, amount)
SeasonClosed(seasonId, carriedToNext)
SeasonSponsored(seasonId, sponsor, gross, netToPool, memo)
PrizeFunded(amount, source)               // source = "mint" | "penalty"
PrizeRequested(drawId, requestId, amount)
PrizeAssigned(drawId, winner, place, amount)
PrizeDrawRecovered(requestId, amount)
PrizeClaimed(winner, amount)
DevWithdrawn(to, amount)
RoyaltyDistributed(royaltyIn, poolAmount, devAmount, genesisAmount, checkpointIdx)
GenesisRoyaltyClaimed(tokenId, holder, amount, checkpointIdx)
```

### 10.3. Custom errors

(Match v1.3 list + new: `GenesisCannotExit`, `GenesisAlreadyFinalized`, `GenesisRaceNotEnded`, `FinalizeWindowExpired`, `LotteryDisabled`, `NoRoyaltyToDistribute`, `NotGenesis`, `NotDormant`, `ZeroAmount`, `InvalidSeason`, `NotActiveAtCheckpoint`, `CheckpointAlreadyClaimed`.)

### 10.4. View helpers

```
function isActive(uint256 tokenId) external view returns (bool);
function maxGrossForMint() external view returns (uint256);
function getEarlyExitPenalty(uint256 tokenId) external view returns (uint256);
function currentSeasonId() external view returns (uint256);
function seasonEnd(uint256 s) external view returns (uint256);
function timeToTransferLockout() external view returns (uint256);  // 0 if currently in lockout
function previewMint(uint256 gross, LockDays lock) external view returns (...);
function previewEffectiveWeight(uint256 tokenId, uint256 seasonId) external view returns (uint256);
function genesisLeaderboard() external view returns (GenesisCandidate[21] memory);
function accountingLiabilities() external view returns (uint256);
function activeGenesisCount() external view returns (uint16);
function activeGenesisIds() external view returns (uint256[] memory);   // O(21)
function pendingGenesisRoyalty(uint256 tokenId, uint256[] calldata idxs) external view returns (uint256);
function canRequestPrizeDraw() external view returns (bool);
function drawSnapshotCount() external view returns (uint256);
```

### 10.5. Constructor

```solidity
constructor(
    address satoToken,
    address devAddress_,
    uint256 prizeMinSato_,
    uint256 prizeDrawInterval_,
    address vrfCoordinator_,
    bytes32 vrfKeyHash_,
    uint256 vrfSubscriptionId_,
    uint16  vrfRequestConfirmations_,
    uint32  vrfCallbackGasLimit_,
    string  memory baseURI_
) ERC721A("Sato Stones Vault", "VSTONE") VRFConsumerBaseV2Plus(vrfCoordinator_)
```

All parameters are immutable. The constructor:
- Reverts if `satoToken == 0 || devAddress_ == 0` (`ZeroAddress`).
- Reverts if `prizeMinSato_ == 0` or `prizeDrawInterval_ < 7 days` or `> 90 days`.
- Reverts if `sato.totalSupply() < 1_000_000 SATO` (bootstrap precondition).
- Sets `t0 = block.timestamp`, `lastPrizeDrawAt = block.timestamp`.

---

## 11. Visual rarity and metadata

| `weightAtMint` | Tier | Visual | Frame |
|----------------|------|--------|-------|
| 0 – 24    | Common   | Grey stone   | Standard |
| 25 – 79   | Uncommon | Blue stone   | Standard |
| 80 – 249  | Rare     | Purple stone | Standard |
| 250+      | Mythic   | Gold stone   | Standard |
| Any, isGenesis | (any tier above) | Tier visual | **Genesis frame** + rank badge |

Required metadata fields per token:

```json
{
  "tokenId": uint,
  "isGenesis": bool,
  "genesisRank": 0..21,
  "isActive": bool,
  "peakSato": uint,
  "currentSatoLocked": uint,
  "lockDurationDays": 30|90|180|365,
  "lockEnd": iso8601,
  "mintTime": iso8601,
  "weightAtMint": uint,
  "rarityTier": "Common"|"Uncommon"|"Rare"|"Mythic",
  "status": "active"|"redeemed"|"burned"
}
```

`baseURI` is immutable; metadata server MUST honor the above schema. Genesis metadata reflects dormant state: while `currentSatoLocked == 0`, set `status: "redeemed"` and `isActive: false` (but `isGenesis: true`).

---

## 12. Solvency invariants (must-test)

Invariant suite (Foundry `invariant_*` tests):

1. **Conservation**: `sato.balanceOf(this) >= accountingLiabilities()` ALWAYS.
2. **Mint balance**: after `mint(g, _)`, `sato.balanceOf(this)` increases by exactly `received`; `sumLocked` increases by `peakSato`; `seasonPool + devBalance + prizeFund` aggregate increases by `received − peakSato − burnFromMintFee`.
3. **Redeem balance**: after `redeem(id)`, contract balance decreases by `satoLocked_pre`; `sumLocked` decreases by same.
4. **EarlyExit balance**: after `earlyExit(id)`, contract balance decreases by `returned + penaltyBurn`; routed buckets sum to `penaltySato`.
5. **Finalize**: sum of `claimAmount[s][*]` plus carry delta plus rounding dust equals `seasonPool[s]_pre + undistributedCarry_pre`.
6. **Claim**: after `claimSeason(s, id)`, contract balance decreases by exactly `claimAmount[s][id]`.
7. **Lottery**: `prizeFund + pendingDrawPrize + sum(pendingPrize)` is non-decreasing except by `claimPrize` (decrement equal to claim).
8. **Genesis**: `isGenesis == true => earlyExit reverts`.
9. **Cap**: per-wallet finalize claim sum ≤ `walletCap`, where wallet = `originalMinter`.
10. **Transfer lockout**: any transfer in `[seasonEnd - 24h, seasonEnd)` reverts.
11. **`maxGrossForMint() >= MIN_GROSS` at all times** (deploy-time precondition + monotone).
12. **Genesis count ≤ 21** and once finalized, immutable.

Coverage target: ≥95% line + branch on `SatoStonesVaultV2.sol`. Fuzz penalty math across all 4 lock periods over the full `[0, lockDays]` second-precision range.

---

## 13. Off-chain operations

### 13.1. Keepers

| Job | Cadence | Function | Failover |
|-----|---------|----------|----------|
| `finalizeSeason` | within 1h after `seasonEnd` (every 30d) | `finalizeSeason(s)` or paginated variant | Public; community can call; FINALIZE_GRACE_PERIOD 14d safety |
| `closeMissedSeason` | day 15 after each `seasonEnd` if not finalized | `closeMissedSeason(s)` | Public |
| `requestPrizeDraw` | every `prizeDrawInterval` (default 30d) | `requestPrizeDraw()` | Public |
| `distributeRoyalty` | weekly | `distributeRoyalty()` | Public |
| `finalizeGenesis` | once at t0+30d | `finalizeGenesis()` | Auto-fallback in `mint()` |
| `recoverTimedOutPrizeDraw` | day after stuck draw | `recoverTimedOutPrizeDraw()` | Public |
| `topUpLINK` | when VRF sub balance < threshold | off-chain (Chainlink subscription manager) | Multisig |

Recommended keeper provider: Gelato Web3 Functions or Chainlink Automation. All keeper jobs MUST be redundant (≥2 providers or include a manual public dashboard with one-click calls).

### 13.2. Indexing

Subgraph (The Graph) MUST index all events listed in §10.2 and expose entities:
- `Stone` (per token): all vault state changes.
- `Season` (per seasonId): pool, totalEffectiveWeight, claims.
- `Minter` (per address): mint count, total locked, total earned, current cap usage.
- `Lottery` (per draw): winners, amounts, eligible minter count.
- `Royalty` (per distribution): amount, splits.
- `Genesis` (per Genesis): score, rank, royalty earned, repledge history.

UI MUST consume subgraph; direct RPC `ownerOf` loops are prohibited at scale (>200 stones).

---

## 14. Risk matrix (post v2.0)

| Risk | Severity | v2.0 mitigation |
|------|----------|-----------------|
| Wallet-cap split sybil | High | `originalMinter` based cap; 24h transfer lockout |
| Late-season pool farming | High | Time-weighted effective weight |
| Whale lottery monopoly | High | 15% per-minter cap; top-3 winners |
| Genesis MEV sniping | Critical | 30-day leaderboard with score floor |
| Genesis flip-empty-frame | Medium | Genesis cannot earlyExit; benefits gated by active status |
| Zero-penalty in final partial day | Medium | 5% floor enforced |
| Forgotten season manipulation | Medium | 14-day finalize grace period; closeMissedSeason carry |
| VRF callback fail | Critical | Inherit `VRFConsumerBaseV2Plus`; per-minter aggregation reduces gas; 750k callback limit |
| VRF subscription drain | Medium | Off-chain monitoring + multisig top-up |
| Finalize gas | High | Paginated variants + bounded by 2100 cap + minter aggregation |
| Reentrancy | Critical | `ReentrancyGuard` on all state-mutating externals + CEI |
| Fee-on-transfer SATO | Medium | Balance-delta intake in mint and sponsor |
| Royalty token mismatch | Medium | Documented: SATO-only royalties; surplus SATO → distributeRoyalty |
| Direct SATO donations | Low | Treated as royalty (intentional); donation is opt-in by donor |
| Genesis race not filled | Low | Spec acknowledges: n ≤ 21 Genesis possible |
| Bootstrap (low SATO supply) | Low | Constructor revert if `sato.totalSupply() < 1M SATO` |
| Self-loop whale (mint→exit→win lottery) | Medium | Lottery cap 15% + top-3 split makes EV negative for self-loop |
| Spec drift | Low | Implementation checklist (§16) enforced in PR |

---

## 15. Tokenomics summary

### 15.1. Inflow / outflow (SATO accounting)

```
Inflows to contract:
  mint:       received SATO (sumLocked += peakSato; rest routed to pool/dev/prize/burn)
  earlyExit:  no SATO in (penalty splits internal SATO)
  redeem:     no SATO in
  sponsor:    received SATO (90% pool, 10% dev)
  royalty:    received SATO via direct transfer (any source)

Outflows:
  redeem:           satoLocked → owner
  earlyExit:        (peakSato − penalty) → owner; penaltyBurn → DEAD
  withdrawDev:      devBalance → devAddress
  claimSeason:      claimAmount → snapshotOwner
  claimPrize:       pendingPrize → winner
  claimGenesisRoyalty: checkpoint share → genesis holder
  mintFeeBurn:      mintFee × 5% → DEAD
```

### 15.2. Expected user APY (model)

Assumptions: 2.1M SATO TVL, 10% annual churn, $50k/mo secondary, SATO @ $0.50.

| Inflow source | SATO/yr to pool | SATO/yr to dev | SATO/yr to Genesis | SATO/yr burn |
|---------------|-----------------|----------------|--------------------|--------------|
| Mint fee (one-time, 4% × 2.1M) | 42 000 | 29 400 | 8 400 | 4 200 |
| Penalty (10% churn) | ~34 000 | ~5 250 | 0 | ~2 600 |
| Royalty ($600k/yr × 5%) | 24 000 | 24 000 | 12 000 | 0 |
| Sponsorship | speculative | speculative | 0 | 0 |
| **Total (yr 1)** | **~100 000** | **~58 650** | **~20 400** | **~6 800** |

Average APY for active locker (1 000 SATO position, average weight): ~67 SATO/yr / 1 000 = **6.7%** base.

Genesis holder additional APY: 20 400 SATO / 21 Genesis = ~970 SATO/yr per Genesis; on a 5 000 SATO Genesis position = **~19.5%** royalty alone, plus the 6.7% base × 1.5× = **10%** pool → **~30% total APY**, plus lottery upside.

Lottery upside (probabilistic): expected value ≈ 1–3% APY for average holder, 3–6% for Genesis.

**Bottom line:**
- Average locker: **7–10% APY** in SATO terms.
- Genesis: **20–30% APY** in SATO terms.
- Plus collectible upside on secondary.

This is competitive with mainstream DeFi while differentiated by the loyalty/community framing.

### 15.3. Project revenue (recurring)

- Penalty 10%: ~5 250 SATO/yr.
- Royalty 40%: ~24 000 SATO/yr.
- Sponsorship 10%: 0–N SATO/yr (speculative).
- Plus mint-fee 35% upfront: 29 400 SATO once the collection is filled.

At $0.50/SATO: **~$14 600 / year recurring + $14 700 upfront**. Sufficient to cover infrastructure, security retainer, and a part-time dev.

---

## 16. Implementation checklist

### 16.1. Contract

- [ ] `SatoStonesVaultV2.sol` inherits `ERC721A`, `ReentrancyGuard`, `VRFConsumerBaseV2Plus`, `IERC2981`.
- [ ] All parameters from §2 immutable, set in constructor.
- [ ] Constructor reverts: zero addresses, `prizeDrawInterval < 7d || > 90d`, `sato.totalSupply() < 1M`.
- [ ] `_startTokenId() = 1`.
- [ ] `_beforeTokenTransfers` enforces TRANSFER_LOCKOUT and writes `seasonEndOwner`.
- [ ] Mint: fee split, fee-on-transfer intake, vault struct, originalMinter, Genesis race update, auto-finalizeGenesis fallback.
- [ ] Genesis race: sorted insertion, candidate eviction, finalize idempotent.
- [ ] earlyExit: ceil days, 5% floor, isGenesis reverts.
- [ ] redeem: returns satoLocked, NFT kept, redeemed=true.
- [ ] repledge: Genesis-only, post-redeem, identical fee path, no mint-count increment.
- [ ] finalizeSeason: single-call + paginated variants; time-weighted; cap by originalMinter; grace period.
- [ ] closeMissedSeason after grace.
- [ ] claimSeason + claimSeasonBatch.
- [ ] sponsorSeason with 90/10 split.
- [ ] Lottery: VRF v2.5 base inheritance, request-time snapshot per minter, 15% cap, top-3.
- [ ] recoverTimedOutPrizeDraw.
- [ ] distributeRoyalty: liability accounting, 40/40/20 split, checkpoint emission.
- [ ] claimGenesisRoyalty.
- [ ] withdrawDev.
- [ ] EIP-2981 `royaltyInfo`, `supportsInterface`.
- [ ] View helpers from §10.4.
- [ ] All custom errors from §10.3.
- [ ] All events from §10.2.

### 16.2. Tests (Foundry)

- [ ] Invariants 1–12 from §12.
- [ ] Fuzz mint (gross × all 4 lock periods × Genesis on/off).
- [ ] Fuzz penalty (per lock period, per second over `[0, lockDays]`).
- [ ] Wallet-cap split: assert cap by `originalMinter` survives 10-way split.
- [ ] Late-season mint: assert effective weight < weightAtMint.
- [ ] Genesis race: 21+ candidates compete, top-21 win, sub-threshold rejected.
- [ ] Genesis cannot earlyExit; repledge works post-redeem.
- [ ] Lottery: top-3 distinct minters; cap 15% applied; VRF callback paths (success, no-eligible, timeout-recover, late-fulfill-rejected).
- [ ] Royalty: distribute splits correctly; Genesis checkpoint claims; donation→distribute.
- [ ] sponsorSeason 90/10.
- [ ] closeMissedSeason after grace.
- [ ] Transfer lockout: exact boundary tests.
- [ ] supportsInterface(0x2a55205a) true.
- [ ] Gas benchmark: finalize at 2 100 stones with 2 100 minters MUST fit in 12M gas (else paginated path is the default).
- [ ] Gas benchmark: lottery fulfill at 2 100 minters MUST fit in 750k callback limit.

### 16.3. Deploy

- [ ] Foundry compile (solc 0.8.24 + Foundry config) is canonical artifact.
- [ ] Deploy script reads Foundry `out/` artifacts; no Node solc divergence.
- [ ] Sepolia deploy uses mocks (separate script).
- [ ] Mainnet deploy: real SATO + Chainlink VRF v2.5 coordinator + funded subscription + add consumer + `--confirm` flag.
- [ ] Mainnet deploy verifies `sato.totalSupply() >= 1M`.
- [ ] Post-deploy: subscribe contract as VRF consumer, fund LINK, register Gelato keepers, deploy subgraph.

### 16.4. Frontend (separate spec update)

- [ ] Pre-lock simulator (peakSato, weight, rarity, expected APY).
- [ ] Earnings dashboard (history, projected, claim CTAs).
- [ ] Genesis leaderboard live during race.
- [ ] Pool dilution forecast on mint screen.
- [ ] Mandatory earlyExit confirmation modal with penalty breakdown.
- [ ] Snapshot-owner-aware claims (read seasonEndOwner via subgraph).
- [ ] Sponsored seasons feed.
- [ ] Wallet event listeners (chainChanged, accountsChanged).
- [ ] Event-based stone discovery (subgraph), no RPC scan.
- [ ] Custom-error decoding via ABI parsing.

---

## 17. Migration / launch plan

v1.3 was never mainnet-deployed (Sepolia only with mocks). **No migration is required.** v2.0 ships as a fresh deploy.

### 17.1. Phased rollout

| Phase | Scope | Exit criteria |
|-------|-------|---------------|
| 0 | Spec freeze (this document) | Approved by team |
| 1 | Contract implementation + Foundry tests + 95% coverage | All invariants pass |
| 2 | Sepolia v2 deploy with mocks; community closed beta 2 weeks | No critical bugs; UX feedback applied |
| 3 | External smart contract audit (recommend: Spearbit / Trail of Bits) | All H/C resolved |
| 4 | Mainnet deploy with t0 = launch block | Verified addresses public |
| 5 | Genesis race t0 → t0 + 30 days; community marketing | finalizeGenesis() called at day 30 |
| 6 | Steady state; first season finalize at t0 + 30 days | Keepers operational |
| 7 (later) | L2 deploy; sponsored season partnerships; governance experiment | Out of v2.0 scope |

### 17.2. Pre-deploy go/no-go

- [ ] External audit signed off
- [ ] All §16.2 tests green on CI
- [ ] Gas benchmarks documented in PR
- [ ] VRF subscription funded with ≥ 6 months of LINK
- [ ] Keepers (Gelato/Chainlink Automation) deployed and tested on Sepolia
- [ ] Subgraph deployed
- [ ] Frontend v2 deployed to production URL
- [ ] Marketing copy aligned (see `marketing-sync.md` v2 update)
- [ ] `devAddress` is a multisig (Gnosis Safe) not an EOA

---

## 18. Decision log (v2.0)

| # | Topic | Decision | Rationale |
|---|-------|----------|-----------|
| 1 | Mint fee | 4% (was 2%), split 50/35/10/5 | Team revenue, sustainable; pool still funded |
| 2 | Lock periods | 30/90/180/365d (was 15/30/60d) | Real loyalty programme |
| 3 | Lock multipliers | 1/2.5/5/10× (was 1/1.8/3×) | Strongly reward long-term |
| 4 | Min gross | 50 SATO (was 100) | Activate Common tier; retail access |
| 5 | Max gross | 50k SATO / 0.5% supply (was 10k / 0.1%) | Whale-friendly |
| 6 | Season duration | 30d (was 15d) | Aligned with min lock; less gaming |
| 7 | Transfer lockout | 24h (was 1h) | Close split-bypass |
| 8 | Wallet cap | 8% by `originalMinter` (was 10% by snapshotOwner) | Sybil-resistant |
| 9 | Snapshot owner | Accumulator via transfer hook (was finalize-time `ownerOf`) | Forgotten-season safety |
| 10 | Pool share | `weight × time-in-season` (was static `weightAtMint`) | Remove late-mint dilution |
| 11 | Penalty split | 65/5/20/10 (was 48/33/15/2) | More to lockers; sustainable dev cut; lower burn |
| 12 | Penalty floor | 5% (was 0% in last partial day) | Remove free-exit cheat |
| 13 | Lottery winners | Top 3 50/30/20 (was 1 winner-take-all) | Distributed wins |
| 14 | Lottery cap | 15% per `originalMinter` (none in v1.3) | Anti-whale |
| 15 | Genesis selection | Top-21 by `genesisScore` after 30d (was first-21 ≥500) | Anti-MEV |
| 16 | Genesis multiplier | 1.5× active-only (was 1.2× always) | Worth competing for |
| 17 | Genesis earlyExit | Forbidden (was allowed) | Anti-flip-frame |
| 18 | Genesis repledge | Allowed post-redeem (not in v1.3) | Keep Genesis productive |
| 19 | Royalty | EIP-2981 5% split 40/40/20 (none in v1.3) | Recurring revenue + Genesis utility |
| 20 | Sponsorship | `sponsorSeason()` 90/10 (none in v1.3) | New revenue/marketing channel |
| 21 | VRF | Chainlink VRF v2.5 via official base (was custom mock-interface) | Mainnet correctness |
| 22 | Callback gas | 750k (was 250k) | Headroom for top-3 + 2100 minters |
| 23 | Finalize grace | 14d (none in v1.3) | Forgotten-season safety |
| 24 | Solvency view | `accountingLiabilities()` (none in v1.3) | Monitoring |
| 25 | Bootstrap precondition | `sato.totalSupply() >= 1M` at deploy | Avoid dead contract |
| 26 | dev address | Multisig recommended | Operational security |

---

## 19. Out of scope (v2.0)

- Governance (voting, proposals). Optional Phase 7.
- L2 deployment. Phase 5+.
- Wrapped Vault NFT (transferable claim rights). Possible v3.
- Liquid staking derivative on Vault NFTs. Out of scope.
- Cross-chain bridging. Out of scope.
- Fiat on-ramp. Out of scope.
- Dynamic / on-chain SVG metadata. Optional Phase 5.
- DAO treasury management. Out of scope.

---

## 20. References

- v1.3 spec (historical): `sato-stones-vault-nft.md`
- Frontend spec: `sato-stones-frontend.md` (update needed for v2)
- Operations runbook: `operations-runbook.md` (update needed for v2)
- Security audit plan: `security-audit-plan.md` (update needed for v2)
- Marketing sync: `marketing-sync.md` (update needed for v2)
- Audit reports: `SMART_CONTRACT_AUDIT.md`, `FRONTEND_DEPLOY_AUDIT.md`, `AUDIT_SUMMARY.md`
- Chainlink VRF v2.5 docs: https://docs.chain.link/vrf/v2-5/overview
- ERC-721A: https://erc721a.org/
- EIP-2981: https://eips.ethereum.org/EIPS/eip-2981
