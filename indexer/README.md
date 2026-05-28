# Sato Stones — Indexer

[Ponder](https://ponder.sh) indexer for the `SatoStonesVault` contract.
Backfills + tails the chain, materializes Stones / owners / draws / events into a
queryable database, and exposes both a **GraphQL** endpoint (auto-generated) and a
small **REST API** (custom routes in `src/api/index.ts`).

## Stack

- **Ponder 0.16** — TypeScript indexer framework. Handles backfill, reorgs, schema migrations, and HTTP.
- **PGlite** (embedded Postgres) for local dev. Drop-in **Postgres** for production via `DATABASE_URL`.
- **Hono** for the custom REST routes.
- **viem** for chain reads inside handlers (e.g. fetching `rarity` from `vaults(tokenId)`).

## Quick start

```bash
cd indexer
cp .env.example .env       # then edit .env with your Sepolia RPC URL
npm install
npm run dev
```

The dev server prints the HTTP URL (default `http://localhost:42069`). It auto-reloads
on schema or handler changes and re-applies migrations safely.

## Scripts

- `npm run dev` — hot-reload dev mode (PGlite).
- `npm run start` — production mode (uses `DATABASE_URL` if set; falls back to PGlite).
- `npm run codegen` — regenerate Ponder TypeScript types.
- `npm run serve` — serve a previously-built indexer (multi-process deploys).
- `npm run lint` — `tsc --noEmit`.

## Environment

| Var | Purpose | Default |
|-----|---------|---------|
| `PONDER_RPC_URL_11155111` | Sepolia JSON-RPC | required for fresh backfills |
| `DATABASE_URL` | Postgres URL | unset → embedded PGlite |
| `VAULT_ADDRESS` | Override contract address | baked-in current Sepolia deploy |
| `VAULT_START_BLOCK` | Override backfill start | baked-in deploy block (10942134) |
| `ALLOWED_ORIGINS` | Comma-separated CORS origins for the API | `*` |

## Schema

See `ponder.schema.ts`. Four tables:

- **`stone`** — one row per minted NFT. Tracks ownership, lock state, claim state, rarity.
- **`owner_stats`** — per-address aggregates. Active stones, total locked, claims, prizes.
- **`global_stats`** — single row, keyed by `id="global"`. Total minted, season state, pools.
- **`draw`** — lottery history: `snapshotting → requested → assigned → claimed | recovered`.
- **`event`** — append-only audit trail. JSON `extra` column for kind-specific fields.

## API

GraphQL (auto-generated from the schema): `GET /graphql` (and `GET /` for GraphiQL).

REST helpers:

- `GET /health`
- `GET /stats` — current global stats
- `GET /stones?owner=0x...&rarity=2&active=true&limit=50&offset=0`
- `GET /stones/:tokenId`
- `GET /owners/:address`
- `GET /draws`
- `GET /events?kind=StoneMinted&actor=0x...&limit=50`
- `GET /leaderboard?limit=25`

All bigints are returned as decimal strings.

## Deployment

The indexer is a long-running Node.js process. Two solid options:

1. **Railway / Render / Fly.io** — point at this folder, set env vars, command `npm run start`.
   Pair with their managed Postgres instance and set `DATABASE_URL`.
2. **Self-hosted (Zo user service)** — register an HTTP service that runs `npm run start` in
   this folder, with `PORT` provided by the platform and Postgres as a sibling user service.

Pin Node `>=18.14`. Persistent disk only matters if you keep using PGlite — production
should always use Postgres so the indexer can scale and survive restarts cleanly.

## Reindexing

To reindex from scratch:

```bash
rm -rf .ponder
npm run dev
```

For a Postgres deployment, drop the schema or set a new `DATABASE_SCHEMA`. Ponder also
ships hot-reload of handler changes — schema-breaking changes will prompt you to wipe.

## Hooking up the frontend

The frontend reads the indexer URL from `window.SATO_STONES_CONFIG.indexerUrl`. The
`web/app/indexer.js` module wraps fetches with a 1.5s timeout and falls back to on-chain
multicall reads when the indexer is unreachable, so the dApp never hard-depends on it.
