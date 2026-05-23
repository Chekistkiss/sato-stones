# Sato Stones Project Audit Summary

Date: 2026-05-23
Scope: `src/SatoStonesVault.sol`, `web/app-vault.js`, deploy scripts, specs, tests.

## Executive Summary

The project is a Solidity vault NFT plus static ethers.js frontend. Core escrow flows are mostly consistent for MVP assumptions, but the project is not mainnet-ready. The highest-risk areas are Chainlink VRF integration, lottery snapshot timing, gas scalability of season/lottery loops, thin test coverage, and frontend/deploy operational footguns.

## Top Risks

### Critical

- Real Chainlink VRF callbacks will not work as implemented. The contract exposes `fulfillRandomWords` directly and does not inherit/implement the real VRF v2.5 consumer callback path.
- The VRF coordinator interface uses an old 5-argument `requestRandomWords` signature, while Chainlink VRF v2.5 uses a struct request with extra args.

### High

- `finalizeSeason` writes snapshots and claim amounts in loops over all minted tokens. At real supply this may exceed block gas and block season finalization.
- `fulfillRandomWords` scans all token IDs twice and likely exceeds the configured callback gas limit as supply grows.
- Lottery eligibility and prize recipient are resolved at VRF fulfill time, not request time, so users can mint, transfer, redeem, or early-exit during the VRF window.
- Frontend claim UI is based on current NFT ownership instead of `snapshotOwner`, causing wrong claim buttons and hiding valid claims after sales.
- Frontend scans `ownerOf(1..totalMintedEver)` over public RPC, which will become unreliable at scale.
- Deploy scripts compile/deploy with different compiler settings than Foundry tests.
- Sepolia deploy script always deploys mocks and overwrites `web/config.js`, making it unsafe as a production deployment path.

### Medium

- `earlyExit` penalty floors `daysRemaining`, allowing zero-penalty early exit in the final partial day before `lockEnd`.
- Tests cover only basic happy paths and do not cover solvency invariants, wallet cap math, real season claims, transfer lockout, full VRF flow, max supply, or fee-on-transfer behavior.
- Frontend lacks account/chain change handlers, proper error decoding for custom errors, mint preflight checks, `previewMint` usage, and early-exit confirmation.
- `web/config.js` is committed while docs imply it is usually ignored.
- Production dependency audit reports low/moderate vulnerabilities through `solc` and `ethers` transitive dependencies.

## Verification Performed

- `npm run vault:dry-run`: passed, with one solc warning about `_beforeTokenTransfers` mutability.
- `node --check web/app-vault.js`: passed.
- `node --check script/deploy-vault-e2e.js` and `script/compile-vault.js`: passed.
- `npm audit --omit=dev`: found 4 vulnerabilities, 2 low and 2 moderate.
- `npm test`: could not run because `forge` is not installed in PATH.
- `codex` CLI review: could not run because `codex` is not installed in PATH.

## Recommended Priority

1. Replace the mock-compatible VRF integration with official Chainlink VRF v2.5 consumer/interface and test on a fork.
2. Redesign lottery and season snapshots so they are bounded and finalized safely under gas limits.
3. Freeze lottery token/owner/weight snapshot at draw request time.
4. Add Foundry invariant and integration tests for solvency, seasons, claims, wallet caps, transfer lockout, supply cap, and VRF.
5. Fix frontend claim ownership logic, O(n) RPC scans, chain/account changes, error decoding, preflight validation, and early-exit confirmation.
6. Split mock Sepolia deploy from production deploy and unify compiler settings between deploy artifacts and tests.

## Related Files

- `SMART_CONTRACT_AUDIT.md`
- `FRONTEND_DEPLOY_AUDIT.md`
