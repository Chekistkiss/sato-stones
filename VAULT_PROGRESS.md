# Sato Stones Vault — progress memory (agent handoff)

> **Read this file first** after any context reset.  
> **Spec:** `_specs/sato-stones-vault-nft.md` v1.3  
## Essence

Vault NFT (2100 max): user locks **100–10k SATO** for **15/30/60d**. **2%** mint fee → season pool. **Early exit** → progressive penalty → 48% pool / 33% burn / 15% prize / 2% dev. After lock: **100% SATO back**, NFT stays. **Genesis** = first **21** mints with **≥500 SATO** (not low tokenId).

## V2 implementation (2026-05-24)

- [x] `src/SatoStonesVaultV2.sol` + `test/SatoStonesVaultV2.t.sol` (23 tests)
- [x] Invariant suite `test/invariant/SatoStonesVaultV2*.sol`
- [x] Gas benchmarks `test/SatoStonesVaultV2Gas.t.sol` (chunked finalize path)
- [x] Deploy: `script/deploy-sepolia-v2-mocks.js`, `script/deploy-mainnet-v2.js`
- [x] Frontend loader: `web/app-vault-v2.js` when `config.vaultVersion === 2`
- [x] Subgraph scaffold `subgraph/`
- [ ] Sepolia V2 deploy + UI smoke test
- [ ] External audit

## What is DONE (MVP session)

- [x] `src/SatoStonesVault.sol` — mint, earlyExit, redeem, seasons (finalize/claim), dev withdraw, VRF lottery
- [x] `script/compile-vault.js` — solc compile → `artifacts/SatoStonesVault.json`
- [x] `script/deploy-vault-e2e.js` — Sepolia deploy + writes `web/config.js`
- [x] `test/SatoStonesVault.t.sol` — basic tests (run with `forge test` if Foundry installed)
- [x] `web/app-vault.js` — connect, mint, redeem, earlyExit, stones list
- [x] `web/index.html` — vault copy, gross+lock mint UI, `app-vault.js`
- [x] `web/config.example.js` — vault template
- [x] `package.json` scripts: `compile:vault`, `vault:dry-run`, `vault:deploy:sepolia`

## Sepolia deploy (2026-05-23)

| Contract | Address |
|----------|---------|
| Mock SATO | `0xF11a35ad806aD930882EBfC075Be0F2116BDB73E` |
| Mock VRF | `0x2D48Ae9820dAB190fF917100429e7093A63c19a4` |
| **SatoStonesVault** | `0xd526B4AF4e63B18c08dd9DB651B25A0433e2c846` |

Deployer wallet: `0xAA2Cbf78f7e4D885D498E074A0e66762393b6C2A` (pre-minted 1M mock SATO).

## What YOU should run (when back)

```bash
npm run compile:vault
npm run vault:dry-run
# .env.sepolia: SEPOLIA_RPC_URL + DEPLOYER_PRIVATE_KEY (or SEPOLIA_PRIVATE_KEY)
npm run vault:deploy:sepolia
npx serve web
# optional: npx vercel --prod
```

## TODO (post-MVP)

- [x] Sepolia deploy (addresses above)
- [ ] Manual UI test: connect MetaMask Sepolia → mint 100+ SATO
- [ ] `forge test --match-contract SatoStonesVault` on machine with Foundry
- [x] Season UI: finalize + claim buttons per season
- [ ] `previewMint` in UI before tx
- [ ] On-chain SVG metadata
- [ ] Heat / Merkle utility (`_specs/sato-stones-utility.md`) — off-chain indexer
- [ ] Mainnet: real SATO `0x829f4B62…`, prizeMinSato tuning, VRF subscription
- [x] Legacy code/docs removed (Vault-only repo)
- [x] Redeploy Sepolia with fixed contract (see addresses above)
- [ ] External audit (`SatoStonesVault` only)

## Key files

| Path | Role |
|------|------|
| `src/SatoStonesVault.sol` | Main contract |
| `artifacts/SatoStonesVault.json` | ABI + bytecode (after compile) |
| `web/app-vault.js` | Vault frontend |
| `web/config.js` | Addresses (gitignored usually) |
| `_specs/sato-stones-vault-nft.md` | Source of truth |

## Known MVP limitations

- Lottery needs VRF fulfill via `MockVRFCoordinator.fulfill` in tests; timed-out draws can be recovered on-chain
- `finalizeSeason` gas loops all tokenIds — OK for 2100
## Changelog

| Date | Change |
|------|--------|
| MVP build | Vault contract compiled; frontend vault mode; deploy script; progress file |
| 2026-05-21 | Sepolia deploy; deploy script accepts `DEPLOYER_PRIVATE_KEY`; shared solc compile for mocks |
| 2026-05-21 | Fix: penalty split 48/33/15/2 + 2% dust→pool; `_startTokenId=1`; VRF request cleanup; public RPC in config |
| 2026-05-21 | Removed Legacy contract, app, sepolia-e2e, specs, `lib/chainlink`, `_site-draft` |
| 2026-05-21 | DrawPending guard; season claim dust→carry; UI read-only RPC + redeem gating; Sepolia redeploy |
| 2026-05-23 | Added `recoverTimedOutPrizeDraw`; Seasons UI for finalize/claim; docs/runbook updated |
| 2026-05-23 | Production Vercel deploy; fixed ethers fallback load order |
| 2026-05-23 | Fixed dark screen: intro class mismatch + removed invisible default section opacity |
| 2026-05-23 | Fixed review findings: all-season UI scan, Genesis preview, VRF mapping cleanup, `.vercelignore`; Sepolia/Vercel redeploy |
| 2026-05-23 | Fixed claim UI to use `snapshotOwner` instead of current NFT owner |
| 2026-05-23 | Redeployed Sepolia after audit fixes: VRF v2.5 callback path, draw snapshot, ceil partial-day penalty, frontend preflight/lottery UX |
| 2026-05-23 | Repo reproducibility: Foundry deps tracked as submodules; public Sepolia `web/config.js` committed for GitHub/Vercel deploys |
| 2026-05-23 | Split deploy scripts: Sepolia mocks are explicit; mainnet deploy has real SATO/VRF envs and confirmation flag |
| 2026-05-23 | Expanded lottery tests: successful draw/claim, request-time owner snapshot, and no-eligible-ticket revert |
