# Sato Stones Frontend and Deploy Audit

Date: 2026-05-23
Scope: `web/app-vault.js`, `web/index.html`, `web/config.js`, `web/config.example.js`, `script/*.js`, `package.json`, frontend and operations specs.

## Executive Summary

The frontend implements the main MVP flows, but several production issues remain. The highest-risk frontend issue is season claim ownership: claim rights belong to `snapshotOwner`, while the UI is based on current ownership. The app also relies on O(n) public RPC scans, has incomplete wallet/network lifecycle handling, and lacks key preflight/error UX. Deployment scripts are useful for Sepolia mocks but unsafe as a production deployment path.

## High Findings

### H1. Season claim UI uses current owner, not snapshot owner

Location: `web/app-vault.js`, `updateSeasonUI`

The contract requires `msg.sender == snapshotOwner[seasonId][tokenId]`, but the UI shows claim rows by iterating `state.userTokenIds`, which contains NFTs currently owned by the connected user.

Failure modes:

- A buyer after season finalize sees a claim button, but transaction reverts with `NotSnapshotOwner`.
- A snapshot owner who sold the NFT still has claim rights but does not see the claim in UI.

Suggested fix: read `snapshotOwner(seasonId, tokenId)` and only show claim buttons when it equals the connected wallet. Consider indexing historical snapshot-owned token IDs.

### H2. User stone discovery is O(totalMinted) RPC scanning

Location: `web/app-vault.js`, `fetchUserStones`

The UI loops from `1` to `state.minted`, calling `ownerOf` for each token and `vaults` for owned tokens.

Failure mode: at 2100 mints, public RPC can rate-limit, timeout, or make wallet connect feel broken.

Suggested fix: use event indexing, a backend/subgraph, multicall batching, local cache, or an on-chain enumerable helper.

### H3. Deploy bytecode can differ from tested bytecode

Location: `script/compile-vault.js`, `foundry.toml`, `package.json`

Node deploy compile uses npm `solc` 0.8.35 with `viaIR: true`. Foundry config uses solc 0.8.24 with `via_ir = false`.

Failure mode: passing Foundry tests does not prove the deployed artifact has the same bytecode behavior/gas profile.

Suggested fix: deploy from Foundry artifacts or align solc version and viaIR settings exactly. Gate deploy on tests.

### H4. Sepolia deploy script is a production footgun

Location: `script/deploy-vault-e2e.js`

The script always deploys a fresh `MockERC20`, fresh `MockVRFCoordinator`, and a vault, then overwrites `web/config.js`.

Failure modes:

- Accidental redeploy overwrites frontend addresses.
- Production deploy could accidentally use mocks or test params.
- Test-only VRF key/interval/prize settings can leak into public config.

Suggested fix: split scripts into `deploy:sepolia:mocks` and `deploy:mainnet`, require an explicit confirm flag, and never overwrite committed config without opt-in.

### H5. Missing `chainChanged` and `accountsChanged` handling

Location: `web/app-vault.js`, `connectWallet`

After connect, if a user changes account or network in wallet, UI state is not reset.

Failure mode: stale signer/account UI can show wrong address/state and produce confusing failed transactions.

Suggested fix: add wallet event listeners, reset app state on account changes, and force reconnect or switch back on wrong network.

### H6. Early exit has no penalty/burn confirmation

Location: `web/app-vault.js`, stone cards and `earlyExitStone`

Early exit burns the NFT and applies a penalty, but the UI provides a one-click button without preview or confirmation.

Failure mode: accidental irreversible exit.

Suggested fix: show a confirmation modal with estimated penalty, returned amount, burn warning, and routing breakdown.

## Medium Findings

### M1. Custom errors are not decoded

Location: `web/app-vault.js`, `parseVaultError`, `VAULT_ABI`

The contract uses custom errors, but the ABI does not include error fragments and `parseVaultError` only truncates the wallet message.

Failure mode: users see generic or unclear transaction failures.

Suggested fix: include error fragments in ABI and use `ethers.Interface.parseError`, or add selector-to-message mapping.

### M2. `previewMint` is declared but unused

Location: `web/app-vault.js`, `updateMintUI`

The UI does not show peak SATO, weight, rarity, or true Genesis eligibility before mint.

Suggested fix: call `previewMint(gross, lock, assumeGenesis)` on input changes and display the result.

### M3. Frontend spec gaps remain

Missing or partial items:

- SATO balance after connect: `#mintSatoBal` exists but is not updated.
- Next stone number: `#mintStoneNum` exists but is not updated.
- Last-hour season transfer lockout warning is missing.
- Lottery request and prize claim actions are missing.
- Error UX mapping is incomplete.

Suggested fix: implement the missing UI pieces from `_specs/sato-stones-frontend.md`.

### M4. Mint flow lacks preflight validation

Location: `approveSato`, `mintVault`

Missing checks:

- SATO balance
- allowance
- wallet mint count
- dynamic max gross
- invalid/empty gross input
- double-submit button locking

Suggested fix: add read preflight and disable buttons when invalid.

### M5. RPC and ethers failures are mostly silent

Location: `DOMContentLoaded`, `fetchGlobal`, `connectWallet`

The page has a connectivity banner, but JS does not wire it for ethers/RPC failures.

Failure mode: users see zero stats or stuck UI with no explanation.

Suggested fix: wrap read paths in try/catch, rotate through `CONFIG.rpcUrls`, and show retry/connectivity UI.

### M6. Network switch lacks add-chain fallback

Location: `connectWallet`

The app calls `wallet_switchEthereumChain`, but if the chain is missing from the wallet it does not call `wallet_addEthereumChain`.

Suggested fix: on wallet error `4902`, call `wallet_addEthereumChain` using config values.

### M7. `web/config.js` is committed despite docs suggesting otherwise

Location: `.gitignore`, `web/config.js`, `VAULT_PROGRESS.md`

Docs say config is usually gitignored, but the actual file is tracked/public in the repo.

Failure mode: config drift and accidental stale deployed addresses.

Suggested fix: commit only `web/config.example.js`, ignore `web/config.js`, and inject production config through deploy/env.

### M8. Lottery UI is incomplete

Location: `web/index.html`, `web/app-vault.js`

The UI shows prize fund and timeout recovery, but not request draw or claim prize. Sepolia mock VRF also requires manual fulfill.

Suggested fix: add `requestPrizeDraw`, `canRequestPrizeDraw`, and `claimPrize` UI, or clearly document keeper-only lottery operations.

### M9. ABI missing useful views/errors

Location: `VAULT_ABI`

Missing items include `requestPrizeDraw`, `claimPrize`, `canRequestPrizeDraw`, `walletMintCount`, and custom errors.

Suggested fix: expand ABI to match frontend needs.

## Low Findings

- `formatSato` converts to `Number`, which can lose precision on large values.
- `LOCK` constant is unused.
- `approveSato` assigns `gross` but does not use it.
- `SATO_ABI` duplicates `balanceOf`.
- Mint/approve buttons do not prevent double submits.
- `mintPausedBanner` is present but never toggled.
- `index.html` loads ethers 6.7.0 from CDN while `package.json` uses ethers 6.16.0.
- Marketing copy does not mention dynamic max gross cap, 10 mints per wallet, or transfer lockout warning.

## Deployment Checklist Risks

### `npm run vault:deploy:sepolia`

- Uses `.env.sepolia` private key.
- Deploys mocks.
- Writes `web/config.js`.
- Uses test VRF parameters.

### `npm run vault:dry-run`

- Compile-only.
- Does not prove Foundry tests pass.
- Does not catch deploy/test compiler divergence.

### `npm run compile:vault`

- Writes `artifacts/SatoStonesVault.json` using npm solc and viaIR.

### `npm test`

- Uses Foundry if installed.
- In the reviewed environment it could not run because `forge` was not in PATH.

## Recommended Priority

1. Fix season claim UI to use `snapshotOwner`.
2. Replace public RPC token scanning with an indexer, multicall, cache, or backend.
3. Unify compiler/deploy/test artifact flow.
4. Harden deploy scripts and config management.
5. Add wallet chain/account lifecycle handling.
6. Add early-exit confirmation and mint preflight.
7. Implement custom error decoding and missing frontend spec items.
