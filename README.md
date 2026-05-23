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
- [Foundry](https://book.getfoundry.sh/) optional (for `forge test`)

Dependencies under `lib/`: OpenZeppelin, ERC721A, forge-std.

### Compile & Sepolia deploy

```bash
npm install
npm run compile:vault
npm run vault:dry-run
npm run vault:deploy:sepolia   # .env.sepolia: SEPOLIA_RPC_URL, DEPLOYER_PRIVATE_KEY
```

Writes `web/config.js` with deployed addresses.

### Foundry tests

```bash
forge test -vv --match-contract SatoStonesVault
```

## Frontend

```bash
npx serve web
```

Copy `web/config.example.js` → `web/config.js` or use output from deploy script.

## Deploy on Vercel

```bash
npx vercel --prod
```

`vercel.json` serves the `web/` folder.

## Mainnet SATO

`0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09` (immutable in production deploy).
