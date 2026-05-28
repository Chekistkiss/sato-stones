# Specification index

## Project context (for new chats)

| Doc | Path | Scope |
|-----|------|--------|
| Vault handoff | [../VAULT_PROGRESS.md](../VAULT_PROGRESS.md) | Deploy status, TODO, commands |

## Feature specs

| Spec | Path | Scope |
|------|------|--------|
| Sato Stones Vault NFT | [sato-stones-vault-nft.md](./sato-stones-vault-nft.md) | Variable SATO lock, penalties, one reward season, pool, lottery |
| Frontend | [sato-stones-frontend.md](./sato-stones-frontend.md) | Wallet, mint/redeem UX, reward claims, errors |
| Utility | [sato-stones-utility.md](./sato-stones-utility.md) | Optional off-chain Heat / future perks |
| Keeper and monitoring runbook | [operations-runbook.md](./operations-runbook.md) | Reward-season finalize, prize draw automation |
| Security audit plan | [security-audit-plan.md](./security-audit-plan.md) | Scope, invariants, pre-mainnet checklist |
| Marketing sync | [marketing-sync.md](./marketing-sync.md) | Public messaging for simplified Vault |

When changing `src/SatoStonesVault.sol` or `web/app-vault.js`, update the matching spec in the same PR.
