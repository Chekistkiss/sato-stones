# Sato Stones — Operations runbook

Permissionless on-chain actions and optional automation for the simplified single-season vault.

## Reward season finalize

Only `seasonId = 0` exists.

1. Read `t0()` and `SEASON_DURATION()`.
2. When `block.timestamp >= t0 + SEASON_DURATION`, call `finalizeSeason(0)`.
3. Log `SeasonFinalized(0, distributable, totalWeight)`.
4. Users claim with `claimSeason(0, tokenId)` if they were `snapshotOwner(0, tokenId)`.

Notes:
- Minting closes at the reward-season end.
- There is no next-season carryover; zero-weight or capped/rounding remainder goes to `prizeFund`.
- Transfers are blocked only during the last hour before the reward-season end, while it is not finalized.

## Prize draw

1. Read `canRequestPrizeDraw()`.
2. If true, anyone can call `requestPrizeDraw()`.
3. If VRF callback does not arrive after `PRIZE_DRAW_TIMEOUT`, call `recoverTimedOutPrizeDraw()`.
4. Winners claim with `claimPrize()`.

## Monitoring

- Alert if `finalizeSeason(0)` is not called within 24h after `t0 + SEASON_DURATION`.
- Alert if `pendingDrawRequestId != 0` for longer than `PRIZE_DRAW_TIMEOUT`.
- Track `devBalance`, `prizeFund`, and contract SATO balance.

## Secrets

Never commit private RPC URLs, deployer keys, or VRF admin secrets. Keep deployment values in `.env*` files or environment variables.
