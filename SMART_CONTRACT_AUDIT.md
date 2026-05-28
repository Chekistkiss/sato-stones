# SatoStonesVault Smart Contract Audit

> Superseded on 2026-05-28 by `AUDIT_SUMMARY.md` after the single-season simplification and chunked gas fixes.

## Current status

The previous audit identified one-transaction season finalization, one-transaction lottery snapshot, 15-day lock eligibility, VRF hardening, and missing invariants as the main blockers.

The current contract has since changed materially:

- `finalizeSeason(0)` is now chunked through `processSeasonSnapshot(0, maxTokens)`.
- Season claims are lazy/pro-rata through `claimableSeasonAmount(0, tokenId)`; precomputed `claimAmount` and the old wallet cap were removed.
- Season eligibility is evaluated at `seasonEnd`, so 15-day Stones minted at `t0` remain eligible.
- `requestPrizeDraw()` now starts a chunked request-time snapshot; `processPrizeDrawSnapshot(maxTokens)` continues it and submits VRF on the final chunk.
- `rawFulfillRandomWords` rejects empty random-word arrays.
- Full-supply chunk tests cover 2,100-Stone season finalization and prize snapshot.

For the current audit, verdict, remaining risks, and verification commands, read `AUDIT_SUMMARY.md`.

## Remaining pre-mainnet priorities

1. Replace the mock-compatible VRF interface with official Chainlink VRF v2.5 consumer contracts and test on a live testnet subscription.
2. Add solvency invariant/fuzz tests.
3. Harden frontend/indexing for production traffic.
4. Confirm the fixed 15-day mint window as a product decision.
5. Run external audit after behavior is frozen.
