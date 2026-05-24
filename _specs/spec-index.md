# Specification index

## Project context (for new chats)

| Doc | Path | Scope |
|-----|------|--------|
| Vault handoff | [../VAULT_PROGRESS.md](../VAULT_PROGRESS.md) | Deploy status, TODO, commands |

## Feature specs

| Spec | Path | Scope |
|------|------|--------|
| **Sato Stones Vault NFT v2.0** (canonical) | [sato-stones-vault-nft-v2.md](./sato-stones-vault-nft-v2.md) | Loyalty vault NFT: 30/90/180/365d locks, 4% mint fee with team revenue split, time-weighted season pool, top-21 Genesis leaderboard, EIP-2981 royalty, top-3 lottery |
| Sato Stones Vault NFT v1.3 (DEPRECATED) | [sato-stones-vault-nft.md](./sato-stones-vault-nft.md) | Historical reference — superseded by v2.0 |
| Frontend | [sato-stones-frontend.md](./sato-stones-frontend.md) | Wallet, mint/redeem UX, errors (NEEDS v2.0 update) |
| Utility and season perks | [sato-stones-utility.md](./sato-stones-utility.md) | Off-chain Heat, seasons, lottery weight policy (NEEDS v2.0 review) |
| Keeper and monitoring runbook | [operations-runbook.md](./operations-runbook.md) | Season finalize, prize draw automation (NEEDS v2.0 update — see v2.0 §13) |
| Security audit plan | [security-audit-plan.md](./security-audit-plan.md) | Scope, invariants, pre-mainnet checklist (NEEDS v2.0 update — see v2.0 §12, §16.2) |
| Marketing sync | [marketing-sync.md](./marketing-sync.md) | Public messaging for Vault / Genesis (NEEDS v2.0 update for top-21 race) |

When changing `src/SatoStonesVault.sol` or `web/app-vault.js`, update the matching spec in the same PR. **All new implementation work targets v2.0 — do not develop against v1.3.**
