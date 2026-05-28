# Sato Stones — Utility specification

Utility V1 is intentionally minimal in the simplified design.

## Principles

- Keep core mint, lock, redeem, early-exit, reward pool, and lottery mechanics simple.
- No special early-mint utility or allowlist tier.
- Any future off-chain Heat or loyalty system must not change the deployed vault accounting unless a new contract version is explicitly specified.

## Possible off-chain Heat V1

Heat can be computed from public chain data after the single reward season:

- active lock duration;
- amount locked (`peakSato`);
- whether the Stone was redeemed normally vs early-exited;
- reward claim participation;
- lottery participation.

Heat is informational until a future release defines concrete perks.

## Deliverables before using Heat publicly

- [ ] Deterministic export script.
- [ ] Public explanation of score inputs.
- [ ] Clear statement that Heat does not affect current on-chain claims or lottery odds.
