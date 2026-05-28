import { onchainTable, primaryKey, relations, index } from "ponder";

// One row per Stone NFT.
export const stone = onchainTable(
  "stone",
  (t) => ({
    tokenId: t.bigint().primaryKey(),
    owner: t.hex().notNull(),
    minter: t.hex().notNull(),
    grossSato: t.bigint().notNull(),
    peakSato: t.bigint().notNull(),
    satoLocked: t.bigint().notNull(),
    lockDays: t.integer().notNull(), // 15 / 30 / 60
    lockEnd: t.bigint().notNull(),
    rarity: t.integer().notNull(), // 0 Common .. 3 Mythic
    weightAtMint: t.bigint().notNull(),
    mintedAt: t.bigint().notNull(),
    mintedBlock: t.bigint().notNull(),
    redeemed: t.boolean().notNull(),
    exited: t.boolean().notNull(),
    exitedAt: t.bigint(),
    redeemedAt: t.bigint(),
    seasonClaimed: t.boolean().notNull(),
    seasonClaimAmount: t.bigint().notNull(),
  }),
  (t) => ({
    ownerIdx: index().on(t.owner),
    rarityIdx: index().on(t.rarity),
    lockDaysIdx: index().on(t.lockDays),
  }),
);

// Owner aggregate — fast lookup for the "your stones" panel without a multicall sweep.
export const ownerStats = onchainTable("owner_stats", (t) => ({
  owner: t.hex().primaryKey(),
  stonesActive: t.integer().notNull(),
  stonesRedeemed: t.integer().notNull(),
  stonesExited: t.integer().notNull(),
  totalLocked: t.bigint().notNull(),
  totalClaimedSeason: t.bigint().notNull(),
  prizesWon: t.integer().notNull(),
  totalPrizeWon: t.bigint().notNull(),
}));

// Global counters; single row keyed by id="global".
export const globalStats = onchainTable("global_stats", (t) => ({
  id: t.text().primaryKey(),
  totalMinted: t.integer().notNull(),
  totalActive: t.integer().notNull(),
  totalRedeemed: t.integer().notNull(),
  totalExited: t.integer().notNull(),
  totalLocked: t.bigint().notNull(),
  totalBurned: t.bigint().notNull(),
  seasonPool: t.bigint().notNull(),
  prizeFund: t.bigint().notNull(),
  devBalance: t.bigint().notNull(),
  seasonFinalized: t.boolean().notNull(),
  seasonDistributable: t.bigint().notNull(),
  seasonTotalWeight: t.bigint().notNull(),
  lastBlock: t.bigint().notNull(),
}));

// Lottery draw history.
export const draw = onchainTable("draw", (t) => ({
  drawId: t.bigint().primaryKey(),
  amount: t.bigint().notNull(),
  status: t.text().notNull(), // "snapshotting" | "requested" | "assigned" | "claimed" | "recovered"
  vrfRequestId: t.bigint(),
  winnerTokenId: t.bigint(),
  winner: t.hex(),
  startedAt: t.bigint().notNull(),
  requestedAt: t.bigint(),
  assignedAt: t.bigint(),
  claimedAt: t.bigint(),
  recoveredAt: t.bigint(),
}));

// Append-only event log (lightweight audit trail for the explorer).
export const event = onchainTable(
  "event",
  (t) => ({
    id: t.text().primaryKey(), // ${blockNumber}-${logIndex}
    kind: t.text().notNull(),
    tokenId: t.bigint(),
    actor: t.hex(),
    amount: t.bigint(),
    extra: t.text(), // JSON blob for kind-specific fields
    blockNumber: t.bigint().notNull(),
    blockTimestamp: t.bigint().notNull(),
    txHash: t.hex().notNull(),
  }),
  (t) => ({
    kindIdx: index().on(t.kind),
    actorIdx: index().on(t.actor),
    tokenIdx: index().on(t.tokenId),
    blockIdx: index().on(t.blockNumber),
  }),
);

export const stoneRelations = relations(stone, ({ one }) => ({
  ownerStats: one(ownerStats, {
    fields: [stone.owner],
    references: [ownerStats.owner],
  }),
}));
