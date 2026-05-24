# SatoStonesVaultV2 — deployment size

After library extraction (`VaultSeasonLib`, `VaultLotteryLib`, `VaultGenesisLib`) and `optimizer_runs = 1`:

- **Vault core runtime**: ~24,416 bytes (under EIP-170 **24,576**)
- **Libraries** (deploy + link before vault): ~4.1 KB combined

`finalizeSeason(uint256)` single-tx finalization was removed; use `finalizeSeasonChunk` + `finalizeSeasonClose` (see gas tests).

Deploy scripts (`deploy-sepolia-v2-mocks.js`, `deploy-mainnet-v2.js`) deploy libraries first, then link into `SatoStonesVaultV2`.

```bash
forge build --sizes | grep -E 'SatoStonesVaultV2|Vault.*Lib'
npm run vault:v2:dry-run
```
