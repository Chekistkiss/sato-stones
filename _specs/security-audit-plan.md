# Sato Stones Vault — External audit plan

## Goal

Independent audit before unrestricted mainnet launch of `SatoStonesVault`.

## Audit scope

- `src/SatoStonesVault.sol`
- `src/interfaces/IVRFCoordinatorV2Plus.sol`
- Critical assumptions: SATO token (no fee-on-transfer on mainnet), VRF coordinator, season accounting.

## High-priority properties

- Mint escrow and fee-on-transfer safe intake; supply cap 2100 (burn does not reopen slots).
- Early-exit penalty math and split (48/33/15/2 + 2% dust → pool).
- Season finalize snapshot, wallet 10% cap, claim only by `snapshotOwner`.
- Contract SATO solvency: locked + pools + prizes ≤ balance.
- VRF fulfill cannot double-pay; reentrancy on mint/exit/redeem/claim.
- No admin pause/upgrade; `withdrawDev` routes to immutable `devAddress`.

## Required artifacts

- `_specs/sato-stones-vault-nft.md` v1.3
- Full `forge test` output + gas report
- Deployed address map (Sepolia + mainnet)
- `operations-runbook.md` for keepers

## Pre-mainnet checklist

- [ ] Audit report with no unresolved Critical/High
- [ ] Mainnet SATO address `0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09`
- [ ] VRF subscription funded; `prizeMinSato` and `prizeDrawInterval` tuned
- [ ] `web/config.js` uses public RPC only (no secrets)
