# Sato Stones — Frontend specification

> Contract: [sato-stones-vault-nft.md](./sato-stones-vault-nft.md) · App: `web/app-vault.js`

## UX flow

1. Home stays app-focused: short hero, live stats, protocol summary, mint, user Stones, seasons/rewards, lottery status, and a short whitepaper CTA.
2. Full protocol whitepaper lives on `/whitepaper/`, not in the main app scroll.
3. Connect wallet → SATO balance, `totalMinted / 2100`, season id, prize pool.
4. Mint: **gross SATO** (100–10k/current dynamic cap), **lock** (15 / 30 / 60 days); show Genesis slots left, next token id, preview `peakSato`, weight, rarity, and wallet/balance/allowance preflight.
5. Approve SATO → `mint(gross, lockDays)`; disable mint until allowance, balance, wallet cap, min deposit, and dynamic max-gross checks pass.
6. Per-NFT: `earlyExit`, `redeem` (after `lockEnd`); show lock countdown. `earlyExit` must confirm NFT burn and estimated penalty/return before submitting.
7. Seasons: finalize any ended unfinalized season; show claims where connected wallet is `snapshotOwner`, even if the NFT was later sold.
8. Copy: 2% mint fee → pool; Genesis = first 21 mints with ≥500 SATO; no curve sell on mint.
9. Warning: last **1 hour** of each season — transfers blocked.
10. Lottery ops: request draw when `canRequestPrizeDraw()` is true; show pending VRF status, 1-day timeout recovery, and `claimPrize()` when `pendingPrize(user) > 0`.
11. Wallet lifecycle: handle `accountsChanged` and `chainChanged` by clearing connected state and prompting reconnect. Network switch should use `wallet_addEthereumChain` fallback for missing chains.
12. Mobile nav collapses into a menu so anchor links do not wrap over the hero/app content.

## Stack

- Static HTML/CSS in `web/`
- ethers.js v6 (CDN + fallback)
- Demo mode when `contractAddress` is zero

## CONFIG (`web/config.js`)

| Field | Description |
|-------|-------------|
| `contractAddress` | `SatoStonesVault` |
| `satoTokenAddress` | SATO ERC20 |
| `chainId` / `chainName` | Target network |
| `rpcUrls` | Public RPC only (no API keys in repo) |
| `explorerBaseUrl` | Etherscan base |

Loaded via `window.SATO_STONES_CONFIG` before `app-vault.js`.

`web/config.js` is committed for public Sepolia deployments so GitHub/Vercel builds are reproducible. It must contain only public addresses and public RPC URLs. Secrets and private RPC keys stay in `.env*` files and must never be referenced from static frontend config.

## Error UX

`#txStatus`: title, message, optional hint. Decode custom errors via the vault ABI where revert data is available; map common reverts (`MintedOut`, `DepositTooLow`, `LockNotEnded`, `DrawPending`, `NoEligibleTickets`, user reject).
