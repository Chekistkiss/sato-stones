# Sato Stones Vault

On-chain NFT collection (2,100 max supply): lock **SATO** in escrow per Stone (15 / 30 / 60 days), one community reward season, progressive early-exit penalties, and a penalty-funded VRF prize pool.

**Spec:** `_specs/sato-stones-vault-nft.md` · **Handoff:** `VAULT_PROGRESS.md`

## Repository layout

```
src/           SatoStonesVault.sol + mocks
test/          Foundry tests
script/        compile and deploy scripts
web/           Static frontend (ethers v6)
_specs/        Product, frontend, operations, and security specs
```

## Core mechanics

- `mint(grossAmount, lockDays)` — lock SATO during the single reward season; 2% fee goes to the reward pool.
- `redeem(tokenId)` — after lock end, return 100% of locked SATO and keep the NFT.
- `earlyExit(tokenId)` — before lock end, burn the NFT and route the progressive penalty to reward pool / burn / prize / dev.
- `finalizeSeason(0)` / `processSeasonSnapshot(0, maxTokens)` / `claimSeason(0, tokenId)` — finalize the one reward season in chunks and claim lazy weighted rewards.
- `requestPrizeDraw` / `processPrizeDrawSnapshot(maxTokens)` / `claimPrize` — snapshot prize tickets in chunks, request VRF, and claim prizes.

There is **no special early-mint NFT tier** in the simplified design. There is also no season wallet cap in the current simplified build; season rewards are pro-rata by eligible Stone weight.

## Setup

Clone with dependencies:

```bash
git clone --recurse-submodules https://github.com/Chekistkiss/sato-stones.git
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

Install JS dependencies:

```bash
npm install
```

## Checks

```bash
npm run compile:vault
npm run vault:dry-run
PATH=/root/.foundry/bin:$PATH forge test -vv --gas-limit 30000000000
```

## Frontend

```bash
npx serve web
```

For local overrides, copy `web/config.example.js` to `web/config.local.js` and load it manually during local testing, or rerun the Sepolia deploy script to rewrite `web/config.js`.

## Deploy on Vercel

```bash
npx vercel --prod
```

`vercel.json` serves the `web/` folder.

## Mainnet SATO

`0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09` (immutable in production deploy).
