# Sato Stones Vault V2 — Subgraph

Indexer scaffold for `SatoStonesVaultV2` events. After deploy:

1. Run `npm run compile:vault` to refresh `artifacts/SatoStonesVaultV2.json`.
2. Set `source.address` and `startBlock` in `subgraph.yaml`.
3. Implement handlers in `src/mapping.ts` (AssemblyScript) — stubs are not included in this repo yet.
4. `graph codegen && graph build && graph deploy`.

Entities: `Stone`, `Season`, `SeasonClaim`, `PrizeDraw`, `RoyaltyDistribution` (see `schema.graphql`).

Frontend should query this subgraph instead of scanning `ownerOf(1..N)` on public RPC.
