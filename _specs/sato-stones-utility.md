# Sato Stones — Utility and season perks specification

## Scope

Utility V1 is intentionally minimal: keep lottery and mint core unchanged while adding retention through 15-day seasons and off-chain Heat accounting.

## Utility model (V1)

- Heat is computed off-chain from chain events and ownership snapshots.
- Heat influences next-season perks first; lottery weighting stays token-based in V1 unless explicitly upgraded in a later contract release.
- Season duration is fixed at 15 days.

## Heat policy

- Base accrual: `1 Heat / day / eligible Stone`.
- Eligibility source for V1 off-chain indexer:
  - default: wallet owns Stone during accrual window;
  - optional stricter mode for V1.1: only staked Stones once staking module exists.
- Transfer penalty and cooldown are not enforced on-chain in V1; if introduced, they must move to contract scope and be documented separately.

## Season outputs (for next season)

- Perks are delivered via off-chain allowlist proofs (Merkle root):
  - tier,
  - early mint start timestamp,
  - discount bps,
  - max discounted mints.
- Suggested tier thresholds for 15-day cadence:
  - None: `0-4`,
  - Bronze: `5-14`,
  - Silver: `15-29`,
  - Gold: `30-44`,
  - Obsidian: `45+`.

## Acceptance criteria

- [ ] One finalized season snapshot every 15 days with reproducible export.
- [ ] Merkle dataset includes wallet, tier, discount, early window, mint cap.
- [ ] UI can show current season countdown and previous season tier.
- [ ] Public docs explain that V1 Heat accounting is off-chain and reproducible from published data.

## Out of scope for V1

- On-chain staking and Heat storage.
- Heat-weighted lottery in contract.
- Reforge / governance / separate reward token.
