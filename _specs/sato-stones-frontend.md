# Sato Stones — Frontend specification

> Contract: [sato-stones-vault-nft.md](./sato-stones-vault-nft.md) · App: `web/app-vault.js`

## UX flow

1. Connect wallet → SATO balance, `totalMinted / 2100`, season id, prize pool.
2. Mint: **gross SATO** (100–10k/current dynamic cap), **lock** (15 / 30 / 60 days); show Genesis slots left, next token id, preview `peakSato`, weight, rarity, and wallet/balance/allowance preflight.
3. Approve SATO → `mint(gross, lockDays)`; disable mint until allowance, balance, wallet cap, min deposit, and dynamic max-gross checks pass.
4. Per-NFT: `earlyExit`, `redeem` (after `lockEnd`); show lock countdown. `earlyExit` must confirm NFT burn and estimated penalty/return before submitting.
5. Seasons: finalize any ended unfinalized season; show claims where connected wallet is `snapshotOwner`, even if the NFT was later sold.
6. Copy: 2% mint fee → pool; Genesis = first 21 mints with ≥500 SATO; no curve sell on mint.
7. Warning: last **1 hour** of each season — transfers blocked.
8. Lottery ops: request draw when `canRequestPrizeDraw()` is true; show pending VRF status, 1-day timeout recovery, and `claimPrize()` when `pendingPrize(user) > 0`.
9. Wallet lifecycle: handle `accountsChanged` and `chainChanged` by clearing connected state and prompting reconnect. Network switch should use `wallet_addEthereumChain` fallback for missing chains.

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

## Error UX

`#txStatus`: title, message, optional hint. Decode custom errors via the vault ABI where revert data is available; map common reverts (`MintedOut`, `DepositTooLow`, `LockNotEnded`, `DrawPending`, `NoEligibleTickets`, user reject).
