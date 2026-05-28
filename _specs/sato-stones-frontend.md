# Sato Stones — Frontend specification

> Contract: [sato-stones-vault-nft.md](./sato-stones-vault-nft.md) · App: `web/app-vault.js`

## UX flow

1. Home stays app-focused: short hero, live stats, protocol summary, mint, user Stones, one reward season, lottery status, and a short whitepaper CTA.
2. Full protocol whitepaper lives on `/whitepaper/`, not in the main app scroll.
3. Connect wallet → SATO balance, `totalMinted / 2100`, reward pool, prize pool.
4. Mint: **gross SATO** (100–10k/current dynamic cap), **lock** (15 / 30 / 60 days); show next token id, preview `peakSato`, weight, rarity, and wallet/balance/allowance preflight.
5. No special early-mint tier or eligibility messaging.
6. Your Stones: list owned token IDs, rarity, peak SATO, lock end, redeem/early-exit actions; early exit requires an explicit confirmation with estimated penalty/return.
7. Season panel: after season end, show whether finalization is not started, in progress, or finalized. Use `seasonSnapshotStarted`, `seasonProcessedUntil`, `seasonFinalized(0)`. The finalize button calls `processSeasonSnapshot(0, maxTokens)` repeatedly until finalized.
8. Claim panel: after finalization, scan user snapshot tokens, call `claimableSeasonAmount(0, tokenId)`, hide claimed/zero rows, and call `claimSeason(0, tokenId)`.
9. Lottery panel: show `prizeFund`, pending VRF draw, active prize snapshot progress (`prizeSnapshotStarted`, `prizeSnapshotNextTokenId`), and user `pendingPrize`.
10. Draw flow: `requestPrizeDraw()` starts a chunked request-time snapshot; if `prizeSnapshotStarted` remains true, show a Continue button that calls `processPrizeDrawSnapshot(maxTokens)` until a VRF request is submitted or no eligible tickets return the prize to the fund.
11. Wallet lifecycle: handle `accountsChanged` and `chainChanged` by clearing connected state and prompting reconnect. Network switch should use `wallet_addEthereumChain` fallback.
12. Config: `web/config.js` is committed for public Sepolia deployments so GitHub/Vercel builds are reproducible. It must contain only public addresses and public RPC URLs. Secrets and private RPC keys stay in `.env*` files and must never be referenced from static frontend config.

## Error UX

`#txStatus`: title, message, optional hint. Decode custom errors via the vault ABI where revert data is available; map common reverts (`MintedOut`, `DepositTooLow`, `SeasonEnded`, `LockNotEnded`, `DrawPending`, user reject). For chunked operations, tell the user when another transaction is needed.
