# SatoStonesVault Smart Contract Audit

Date: 2026-05-23
Scope: `src/SatoStonesVault.sol`, `src/interfaces/IVRFCoordinatorV2Plus.sol`, tests, and vault/security specs.

## Executive Summary

Core escrow accounting appears internally consistent under the standard ERC-20 SATO assumption. Mint, redeem, early exit, penalty split, and supply cap logic broadly match the vault spec. The mainnet lottery implementation is not production-ready: the VRF integration is mock-compatible but not Chainlink VRF v2.5-compatible, callback gas does not scale, and draw eligibility is not snapshotted at request time.

## Critical Findings

### C1. Real Chainlink VRF callback will not fire

Location: `src/SatoStonesVault.sol`, `fulfillRandomWords`

The contract exposes `fulfillRandomWords(uint256,uint256[])` externally and checks `msg.sender == vrfCoordinator`. Real Chainlink VRF consumers normally inherit `VRFConsumerBaseV2Plus`, receive callbacks through `rawFulfillRandomWords`, and override an internal `fulfillRandomWords`.

Failure mode: `requestPrizeDraw()` can leave `pendingDrawPrize` stuck until timeout recovery because the real coordinator callback will not hit the expected consumer flow.

Suggested fix: inherit the official Chainlink VRF v2.5 consumer base or implement the exact `rawFulfillRandomWords` entrypoint expected by the coordinator, then make fulfillment internal.

### C2. VRF v2.5 request interface mismatch

Location: `src/interfaces/IVRFCoordinatorV2Plus.sol`, `requestPrizeDraw`

The local interface uses a legacy 5-argument `requestRandomWords` signature. Chainlink VRF v2.5 uses a `RandomWordsRequest` struct with `extraArgs`.

Failure mode: calls to the real coordinator are likely selector-incompatible and revert.

Suggested fix: import official Chainlink interfaces/libraries and build the v2.5 request struct. Add deployment steps for subscription consumer setup.

## High Findings

### H1. VRF callback gas likely insufficient at scale

Location: `src/SatoStonesVault.sol`, `fulfillRandomWords`; `script/deploy-vault-e2e.js`

The callback scans all minted token IDs twice. The deploy script configures `vrfCallbackGasLimit` as `250000`, which is unlikely to handle hundreds or thousands of active stones.

Failure mode: VRF callback runs out of gas, request is billed, prize remains pending until timeout recovery.

Suggested fix: benchmark callback gas by active supply, raise callback gas with headroom, or redesign draw storage so fulfillment is bounded.

### H2. Lottery eligibility is resolved at fulfill time

Location: `src/SatoStonesVault.sol`, `requestPrizeDraw`, `fulfillRandomWords`

The contract transfers `prizeFund` to `pendingDrawPrize` at request time, but eligible tickets, weights, and winner owner are calculated when VRF fulfills.

Failure mode: users can mint, transfer, redeem, or early-exit during the VRF window and change who is eligible or who receives the prize.

Suggested fix: snapshot eligible token IDs, weights, and owner at request time. Fulfillment should only consume the frozen snapshot.

### H3. Season finalization can become gas-bound

Location: `src/SatoStonesVault.sol`, `finalizeSeason`, `_applyWalletCapAndSetClaims`

Finalization loops over `totalMintedEver`, writes `snapshotOwner`, then loops again to precompute claims. The wallet cap helper also does wallet lookup with linear scans.

Failure mode: at real supply, season finalization may exceed block gas and make seasonal rewards unclaimable until redesigned.

Suggested fix: use paginated finalization, Merkle/off-chain claim generation, or another bounded accounting design.

### H4. Test coverage is below pre-mainnet requirements

Location: `test/SatoStonesVault.t.sol`, `_specs/security-audit-plan.md`

Missing coverage includes solvency invariants, wallet cap scaling, claim authorization, full season claim flow, VRF winner claim, transfer lockout, max supply, max mints per wallet, penalty fuzzing, and fee-on-transfer intake.

Suggested fix: add invariant tests and integration tests before external audit or mainnet launch.

### H5. Minimum mint can be impossible if SATO supply is too small

Location: `src/SatoStonesVault.sol`, `_maxGrossForMint`

Max gross is `min(10000 SATO, 0.1% totalSupply)`, while minimum gross is `100 SATO`.

Failure mode: if SATO total supply is below `100000 SATO`, `maxGross < MIN_GROSS`, so all mints revert.

Suggested fix: document the deploy precondition or change the cap logic to include a bootstrap floor.

## Medium Findings

### M1. Zero-penalty early exit in final partial day

Location: `src/SatoStonesVault.sol`, `_penaltySato`

`daysRemaining = (lockEnd - now) / 1 days` floors to zero when less than 24 hours remain.

Failure mode: user can early-exit before lock end with zero penalty, getting full escrow back while burning the NFT. Rational users should redeem later, but the protocol loses expected late penalty behavior.

Suggested fix: ceil partial days, clamp to at least 1 while locked, or disable early exit when computed penalty is zero.

### M2. Missed season finalization locks funds operationally

Location: `src/SatoStonesVault.sol`, `seasonPool`, `finalizeSeason`

Each season must be finalized separately. If keepers miss seasons, funds remain accounted but not claimable.

Suggested fix: add keeper monitoring, batch finalize helpers, or clearer user-facing status.

### M3. Failed prize draw remains stuck for a full interval

Location: `src/SatoStonesVault.sol`, `recoverTimedOutPrizeDraw`

Recovery is only possible after `lastPrizeDrawAt + prizeDrawInterval`.

Failure mode: failed callback can lock prize funds for the full interval before retry.

Suggested fix: separate draw request timestamp from draw interval and use a shorter callback timeout.

### M4. Prize winner address can change during VRF window

Location: `src/SatoStonesVault.sol`, `ownerOf(winnerId)` in fulfillment

Winner payout is assigned to the owner at fulfillment time, not owner at request/snapshot time.

Suggested fix: snapshot owner with the ticket set.

### M5. Spec drift around wallet cap timing

Location: `_specs/sato-stones-vault-nft.md`, `src/SatoStonesVault.sol`

Spec prose mentions claim-time wallet cap, while code precomputes claim amounts at finalize. The decision log appears to support finalize-time behavior.

Suggested fix: update the spec prose to match the implementation.

### M6. Rarity threshold ambiguity

Location: `_rarityFromWeight`, vault spec rarity table

Code treats weight `15` as Uncommon, while the spec table says `0-15` Common.

Suggested fix: decide inclusive bounds and update code/spec accordingly.

### M7. `previewMint` assumes no fee-on-transfer

Location: `previewMint`

Preview assumes `received == grossAmount`, while real mint uses balance delta. This is acceptable only if mainnet SATO has no transfer fee.

Suggested fix: document the hard assumption or expose preview caveat in UI.

### M8. External fulfillment lacks `nonReentrant`

Location: `fulfillRandomWords`

There are no token transfers in fulfillment today, but it is an external state-mutating entrypoint.

Suggested fix: add `nonReentrant` or use internal Chainlink callback override through the base consumer.

## Low Findings

- Empty eligible pool during VRF fulfillment silently returns prize to `prizeFund` without a dedicated event.
- Zero VRF coordinator produces misleading `PrizeDrawTooSoon` behavior instead of a dedicated disabled error.
- Direct SATO donations create extra balance not represented in liabilities.
- No on-chain `accountingLiabilities()` helper for monitoring solvency.
- Spec implementation checklist remains mostly unchecked.

## Solvency Notes

Under a standard non-rebasing, non-fee-on-transfer SATO token:

- Mint increases contract balance by received SATO and allocates it between `peakSato` and season pool.
- Redeem zeroes locked balance and transfers escrow to owner.
- Early exit zeroes locked balance, returns user share, burns burn share, and records pool/prize/dev shares.
- Finalize only turns season pool/carry into claim accounting.
- Claim transfers precomputed claim amount once.

No direct double-spend or over-allocation path was found in manual review, but this needs invariant testing before launch.

## Required Pre-Mainnet Work

1. Replace VRF mock-compatible integration with official Chainlink VRF v2.5.
2. Benchmark and redesign gas-heavy season and lottery loops.
3. Snapshot lottery eligibility at request time.
4. Add invariant and integration tests for the full accounting lifecycle.
5. Resolve penalty floor and spec drift.
6. Run external audit with full Foundry test and gas reports.
