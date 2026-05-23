# Sato Stones Vault

On-chain NFT collection (2,100 supply): lock **SATO** in escrow per stone (15 / 30 / 60 days), seasonal community pool, progressive early-exit penalties, Genesis for the first 21 mints with ≥500 SATO.

**Spec:** `_specs/sato-stones-vault-nft.md` · **Handoff:** `VAULT_PROGRESS.md`

## Repository layout

```
src/           SatoStonesVault.sol + mocks
test/          Foundry tests
script/        compile-vault.js, deploy-vault-e2e.js
web/           Static frontend (ethers v6)
_specs/        Specifications
```

## Smart contracts

| Contract | Role |
|----------|------|
| `SatoStonesVault.sol` | Lock SATO, seasons, penalties, Genesis, VRF lottery |
| `mocks/MockERC20.sol`, `MockVRFCoordinator.sol` | Sepolia / local tests |

### Key functions

- `mint(grossAmount, lockDays)` — lock SATO (2% fee → season pool)
- `earlyExit(tokenId)` — progressive penalty; burns NFT
- `redeem(tokenId)` — full SATO back after lock; NFT kept
- `finalizeSeason` / `claimSeason` — seasonal pool distribution
- `requestPrizeDraw` / `claimPrize` — lottery from penalty-funded pool

## Development

### Prerequisites

- Node.js 18+ for compile/deploy scripts
- [Foundry](https://book.getfoundry.sh/) for contract tests and remappings

Dependencies under `lib/` are tracked as git submodules: OpenZeppelin, ERC721A, forge-std.

Clone with dependencies:

```bash
git clone --recurse-submodules https://github.com/Chekistkiss/sato-stones.git
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

### Compile & Sepolia deploy with mocks

```bash
npm install
npm run compile:vault
npm run vault:dry-run
npm run vault:deploy:sepolia:mocks   # .env.sepolia: SEPOLIA_RPC_URL, DEPLOYER_PRIVATE_KEY
```

Writes `web/config.js` with deployed addresses. The committed `web/config.js` is public Sepolia config so GitHub/Vercel deploys work without local-only files.

### Mainnet deploy

Mainnet deploy is intentionally separate and never deploys mocks:

```bash
npm run vault:deploy:mainnet:dry-run
npm run vault:deploy:mainnet
```

Required `.env.mainnet`: `MAINNET_RPC_URL`, `MAINNET_PRIVATE_KEY` or `DEPLOYER_PRIVATE_KEY`, `PRIZE_MIN_SATO`, `VRF_COORDINATOR`, `VRF_KEY_HASH`, `VRF_SUBSCRIPTION_ID`. Optional: `SATO_TOKEN_ADDRESS` (defaults to mainnet SATO), `DEV_ADDRESS`, `PRIZE_DRAW_INTERVAL_SECONDS`, `VRF_CONFIRMATIONS`, `VRF_CALLBACK_GAS_LIMIT`, `BASE_URI`.

### Foundry tests

```bash
forge test -vv --match-contract SatoStonesVault
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
