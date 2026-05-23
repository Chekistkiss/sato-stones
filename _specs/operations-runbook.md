# Sato Stones Vault — Operations runbook

## Scope

Permissionless on-chain actions and optional automation for seasons and lottery on mainnet.

## Keeper jobs (optional bots)

### Season finalize (after each 15-day season ends)

1. Read `currentSeasonId()` and previous `seasonId = current - 1` (if season > 0).
2. When `block.timestamp >= t0 + (seasonId + 1) * 15 days`, call `finalizeSeason(seasonId)`.
3. Log `SeasonFinalized` and `distributable` / `totalWeight`.

### Prize draw (when pool ready)

1. Read `canRequestPrizeDraw()`.
2. If true, call `requestPrizeDraw()`; the contract snapshots active locked stones and waits for Chainlink VRF v2.5 callback to `rawFulfillRandomWords`.
3. Winner claims via `claimPrize()` (pull pattern).
4. If `pendingDrawPrize > 0` and `block.timestamp >= lastPrizeDrawAt + PRIZE_DRAW_TIMEOUT` (1 day), call `recoverTimedOutPrizeDraw()` and retry the draw after the interval condition is met again.

### Dev withdraw

Anyone may call `withdrawDev()`; SATO goes to immutable `devAddress` (2% of penalties only).

## Monitoring

- Alert if `seasonPool[currentSeason]` grows but no `finalizeSeason` within 24h after season end.
- Alert if `prizeFund >= prizeMinSato` and no `requestPrizeDraw` within `2 × prizeDrawInterval`.
- Alert if `pendingDrawPrize > 0` past `lastPrizeDrawAt + PRIZE_DRAW_TIMEOUT` (recoverable timeout).
- Alert if contract SATO balance < sum of outstanding `satoLocked` (invariant break).

## Incidents

- **Stuck VRF:** verify subscription LINK. If timeout elapsed, call `recoverTimedOutPrizeDraw()`; late callbacks from the recovered request are rejected by request ID.
- **Transfer lockout:** last 1h of each season — expected; do not panic.
