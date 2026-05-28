// Custom HTTP API on top of Ponder's HTTP server.
// Lives alongside the auto-generated GraphQL at /graphql.

import { Hono } from "hono";
import { cors } from "hono/cors";
import { graphql, and, desc, eq, or } from "ponder";
import { db } from "ponder:api";
import schema from "ponder:schema";

const app = new Hono();

const allowed = (process.env.ALLOWED_ORIGINS ?? "*")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

app.use("*", cors({ origin: allowed.includes("*") ? "*" : allowed }));

// Mount Ponder's GraphQL at /graphql.
app.use("/graphql", graphql({ db, schema }));

// ---- REST endpoints ----

function bigintReplacer(_k: string, v: unknown) {
  return typeof v === "bigint" ? v.toString() : v;
}

function json(c: any, data: unknown, status = 200) {
  c.header("content-type", "application/json; charset=utf-8");
  return c.body(JSON.stringify(data, bigintReplacer), status);
}

app.get("/info", (c) => json(c, { ok: true, t: Date.now(), name: "sato-stones-indexer" }));

app.get("/stats", async (c) => {
  const rows = await db
    .select()
    .from(schema.globalStats)
    .where(eq(schema.globalStats.id, "global"))
    .limit(1);
  return json(c, rows[0] ?? null);
});

app.get("/stones", async (c) => {
  const url = new URL(c.req.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "50", 10) || 50, 200);
  const offset = Math.max(parseInt(url.searchParams.get("offset") ?? "0", 10) || 0, 0);
  const owner = url.searchParams.get("owner");
  const rarity = url.searchParams.get("rarity");
  const active = url.searchParams.get("active");

  const conds: any[] = [];
  if (owner) conds.push(eq(schema.stone.owner, owner.toLowerCase() as `0x${string}`));
  if (rarity !== null && rarity !== undefined) conds.push(eq(schema.stone.rarity, parseInt(rarity, 10)));
  if (active === "true") {
    conds.push(eq(schema.stone.redeemed, false));
    conds.push(eq(schema.stone.exited, false));
  } else if (active === "false") {
    conds.push(or(eq(schema.stone.redeemed, true), eq(schema.stone.exited, true)));
  }

  const where = conds.length ? and(...conds) : undefined;
  const rows = await db
    .select()
    .from(schema.stone)
    .where(where as any)
    .orderBy(desc(schema.stone.tokenId))
    .limit(limit)
    .offset(offset);
  return json(c, { rows, limit, offset });
});

app.get("/stones/:tokenId", async (c) => {
  let tokenId: bigint;
  try { tokenId = BigInt(c.req.param("tokenId")); } catch { return json(c, { error: "bad_token_id" }, 400); }
  const rows = await db
    .select()
    .from(schema.stone)
    .where(eq(schema.stone.tokenId, tokenId))
    .limit(1);
  if (!rows[0]) return json(c, { error: "not_found" }, 404);
  return json(c, rows[0]);
});

app.get("/owners/:address", async (c) => {
  const addr = c.req.param("address").toLowerCase() as `0x${string}`;
  const [ownerRow, stones] = await Promise.all([
    db.select().from(schema.ownerStats).where(eq(schema.ownerStats.owner, addr)).limit(1),
    db.select().from(schema.stone).where(eq(schema.stone.owner, addr)).orderBy(schema.stone.tokenId),
  ]);
  return json(c, { owner: addr, stats: ownerRow[0] ?? null, stones });
});

app.get("/draws", async (c) => {
  const rows = await db.select().from(schema.draw).orderBy(desc(schema.draw.drawId)).limit(50);
  return json(c, { rows });
});

app.get("/events", async (c) => {
  const url = new URL(c.req.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "50", 10) || 50, 500);
  const kind = url.searchParams.get("kind");
  const actor = url.searchParams.get("actor");
  const conds: any[] = [];
  if (kind) conds.push(eq(schema.event.kind, kind));
  if (actor) conds.push(eq(schema.event.actor, actor.toLowerCase() as `0x${string}`));
  const where = conds.length ? and(...conds) : undefined;
  const rows = await db
    .select()
    .from(schema.event)
    .where(where as any)
    .orderBy(desc(schema.event.blockNumber))
    .limit(limit);
  return json(c, { rows });
});

app.get("/leaderboard", async (c) => {
  const url = new URL(c.req.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "25", 10) || 25, 100);
  const rows = await db
    .select()
    .from(schema.ownerStats)
    .orderBy(desc(schema.ownerStats.totalLocked))
    .limit(limit);
  return json(c, { rows });
});

export default app;
