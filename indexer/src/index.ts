// @ts-nocheck — Ponder/Drizzle handler types over-narrow nullable updates; runtime is correct.
import { ponder } from "ponder:registry";
import { stone, ownerStats, globalStats, draw, event } from "ponder:schema";
import { and, eq, desc } from "ponder";

const GLOBAL_KEY = "global";
const ZERO_ADDR = "0x0000000000000000000000000000000000000000" as const;

// Map LockDays enum -> day count.
const LOCK_DAYS: Record<number, number> = { 0: 15, 1: 30, 2: 60 };

function eventId(ev: { block: { number: bigint }; log: { logIndex: number } }) {
  return `${ev.block.number.toString()}-${ev.log.logIndex}`;
}

async function bumpGlobal(
  db: any,
  patch: Partial<{
    totalMinted: number;
    totalActive: number;
    totalRedeemed: number;
    totalExited: number;
    totalLocked: bigint;
    totalBurned: bigint;
    seasonPool: bigint;
    prizeFund: bigint;
    devBalance: bigint;
    seasonFinalized: boolean;
    seasonDistributable: bigint;
    seasonTotalWeight: bigint;
    lastBlock: bigint;
  }>,
) {
  const cur = await db.find(globalStats, { id: GLOBAL_KEY });
  if (!cur) {
    await db.insert(globalStats).values({
      id: GLOBAL_KEY,
      totalMinted: 0,
      totalActive: 0,
      totalRedeemed: 0,
      totalExited: 0,
      totalLocked: 0n,
      totalBurned: 0n,
      seasonPool: 0n,
      prizeFund: 0n,
      devBalance: 0n,
      seasonFinalized: false,
      seasonDistributable: 0n,
      seasonTotalWeight: 0n,
      lastBlock: 0n,
      ...patch,
    });
    return;
  }
  const next: any = { ...cur };
  for (const [k, v] of Object.entries(patch)) {
    if (typeof v === "number" || typeof v === "bigint") {
      // additive ints/bigints
      next[k] = (cur as any)[k] + (v as any);
    } else {
      next[k] = v;
    }
  }
  await db.update(globalStats, { id: GLOBAL_KEY }).set(next);
}

async function bumpOwner(db: any, owner: `0x${string}`, patch: any) {
  if (owner.toLowerCase() === ZERO_ADDR) return;
  const cur = await db.find(ownerStats, { owner });
  if (!cur) {
    await db.insert(ownerStats).values({
      owner,
      stonesActive: 0,
      stonesRedeemed: 0,
      stonesExited: 0,
      totalLocked: 0n,
      totalClaimedSeason: 0n,
      prizesWon: 0,
      totalPrizeWon: 0n,
      ...patch,
    });
    return;
  }
  const next: any = { ...cur };
  for (const [k, v] of Object.entries(patch)) {
    next[k] = (cur as any)[k] + (v as any);
  }
  await db.update(ownerStats, { owner }).set(next);
}

async function logEvent(
  db: any,
  ev: any,
  kind: string,
  patch: {
    tokenId?: bigint;
    actor?: `0x${string}`;
    amount?: bigint;
    extra?: Record<string, unknown>;
  } = {},
) {
  await db.insert(event).values({
    id: eventId(ev),
    kind,
    tokenId: patch.tokenId ?? null,
    actor: patch.actor ?? null,
    amount: patch.amount ?? null,
    extra: patch.extra ? JSON.stringify(patch.extra) : null,
    blockNumber: ev.block.number,
    blockTimestamp: ev.block.timestamp,
    txHash: ev.transaction.hash,
  });
}

ponder.on("SatoStonesVault:StoneMinted", async ({ event: ev, context }) => {
  const { minter, tokenId, grossSato, peakSato, lockDays, weightAtMint } = ev.args;
  const days = LOCK_DAYS[lockDays] ?? Number(lockDays);
  const lockEnd = ev.block.timestamp + BigInt(days) * 86_400n;

  // Read rarity + canonical satoLocked from chain at this block.
  let rarity = 0;
  let satoLocked = peakSato;
  try {
    const v = (await context.client.readContract({
      abi: context.contracts.SatoStonesVault.abi,
      address: context.contracts.SatoStonesVault.address,
      functionName: "vaults",
      args: [tokenId],
      blockNumber: ev.block.number,
    })) as any[];
    // vaults returns: peakSato, satoLocked, lockEnd, weightAtMint, redeemed?, rarity, redeemedBool
    // Match the tuple order from current contract.
    satoLocked = BigInt(v[1] ?? satoLocked);
    rarity = Number(v[5] ?? 0);
  } catch {
    // fall back to defaults
  }

  await context.db.insert(stone).values({
    tokenId,
    owner: minter,
    minter,
    grossSato,
    peakSato,
    satoLocked,
    lockDays: days,
    lockEnd,
    rarity,
    weightAtMint: BigInt(weightAtMint),
    mintedAt: ev.block.timestamp,
    mintedBlock: ev.block.number,
    redeemed: false,
    exited: false,
    exitedAt: null,
    redeemedAt: null,
    seasonClaimed: false,
    seasonClaimAmount: 0n,
  });

  await bumpOwner(context.db, minter, {
    stonesActive: 1,
    totalLocked: satoLocked,
  });

  await bumpGlobal(context.db, {
    totalMinted: 1,
    totalActive: 1,
    totalLocked: satoLocked,
    lastBlock: ev.block.number,
  });

  await logEvent(context.db, ev, "StoneMinted", {
    tokenId,
    actor: minter,
    amount: grossSato,
    extra: { peakSato: peakSato.toString(), lockDays: days, weight: weightAtMint.toString(), rarity },
  });
});

ponder.on("SatoStonesVault:EarlyExit", async ({ event: ev, context }) => {
  const { tokenId, owner, penaltySato, returnedSato } = ev.args;
  const cur = await context.db.find(stone, { tokenId });
  if (cur) {
    await context.db.update(stone, { tokenId }).set({
      exited: true,
      exitedAt: ev.block.timestamp,
      satoLocked: 0n,
    });
    await bumpOwner(context.db, cur.owner, {
      stonesActive: -1,
      stonesExited: 1,
      totalLocked: -cur.satoLocked,
    });
    await bumpGlobal(context.db, {
      totalActive: -1,
      totalExited: 1,
      totalLocked: -cur.satoLocked,
      lastBlock: ev.block.number,
    });
  }
  await logEvent(context.db, ev, "EarlyExit", {
    tokenId,
    actor: owner,
    amount: returnedSato,
    extra: { penaltySato: penaltySato.toString() },
  });
});

ponder.on("SatoStonesVault:Redeemed", async ({ event: ev, context }) => {
  const { tokenId, owner, satoReturned } = ev.args;
  const cur = await context.db.find(stone, { tokenId });
  if (cur) {
    await context.db.update(stone, { tokenId }).set({
      redeemed: true,
      redeemedAt: ev.block.timestamp,
      satoLocked: 0n,
    });
    await bumpOwner(context.db, cur.owner, {
      stonesActive: -1,
      stonesRedeemed: 1,
      totalLocked: -cur.satoLocked,
    });
    await bumpGlobal(context.db, {
      totalActive: -1,
      totalRedeemed: 1,
      totalLocked: -cur.satoLocked,
      lastBlock: ev.block.number,
    });
  }
  await logEvent(context.db, ev, "Redeemed", {
    tokenId,
    actor: owner,
    amount: satoReturned,
  });
});

ponder.on("SatoStonesVault:SeasonFinalized", async ({ event: ev, context }) => {
  const { distributable, totalWeight } = ev.args;
  await bumpGlobal(context.db, {
    seasonFinalized: true,
    seasonDistributable: distributable,
    seasonTotalWeight: totalWeight,
    lastBlock: ev.block.number,
  });
  await logEvent(context.db, ev, "SeasonFinalized", {
    amount: distributable,
    extra: { totalWeight: totalWeight.toString() },
  });
});

ponder.on("SatoStonesVault:SeasonClaimed", async ({ event: ev, context }) => {
  const { tokenId, claimant, amount } = ev.args;
  const cur = await context.db.find(stone, { tokenId });
  if (cur) {
    await context.db.update(stone, { tokenId }).set({
      seasonClaimed: true,
      seasonClaimAmount: amount,
    });
  }
  await bumpOwner(context.db, claimant, { totalClaimedSeason: amount });
  await logEvent(context.db, ev, "SeasonClaimed", {
    tokenId,
    actor: claimant,
    amount,
  });
});

ponder.on("SatoStonesVault:PrizeFunded", async ({ event: ev, context }) => {
  await bumpGlobal(context.db, { prizeFund: ev.args.amount, lastBlock: ev.block.number });
  await logEvent(context.db, ev, "PrizeFunded", { amount: ev.args.amount });
});

ponder.on("SatoStonesVault:PrizeSnapshotStarted", async ({ event: ev, context }) => {
  const { drawId, amount } = ev.args;
  await context.db.insert(draw).values({
    drawId,
    amount,
    status: "snapshotting",
    vrfRequestId: null,
    winnerTokenId: null,
    winner: null,
    startedAt: ev.block.timestamp,
    requestedAt: null,
    assignedAt: null,
    claimedAt: null,
    recoveredAt: null,
  });
  await logEvent(context.db, ev, "PrizeSnapshotStarted", { amount, extra: { drawId: drawId.toString() } });
});

ponder.on("SatoStonesVault:PrizeRequested", async ({ event: ev, context }) => {
  const { drawId, requestId, amount } = ev.args;
  await context.db.update(draw, { drawId }).set({
    status: "requested",
    vrfRequestId: requestId,
    requestedAt: ev.block.timestamp,
  });
  await logEvent(context.db, ev, "PrizeRequested", {
    amount,
    extra: { drawId: drawId.toString(), vrfRequestId: requestId.toString() },
  });
});

ponder.on("SatoStonesVault:PrizeAssigned", async ({ event: ev, context }) => {
  const { drawId, winnerTokenId, winner, amount } = ev.args;
  await context.db.update(draw, { drawId }).set({
    status: "assigned",
    winnerTokenId,
    winner,
    assignedAt: ev.block.timestamp,
  });
  await logEvent(context.db, ev, "PrizeAssigned", {
    tokenId: winnerTokenId,
    actor: winner,
    amount,
    extra: { drawId: drawId.toString() },
  });
});

ponder.on("SatoStonesVault:PrizeClaimed", async ({ event: ev, context }) => {
  const { winner, amount } = ev.args;
  // Mark the most recent assigned draw for this winner as claimed.
  const recent = await context.db.sql
    .select()
    .from(draw)
    .where(and(eq(draw.winner, winner), eq(draw.status, "assigned")))
    .orderBy(desc(draw.drawId))
    .limit(1);
  const last = recent[0];
  if (last) {
    await context.db.update(draw, { drawId: last.drawId }).set({
      status: "claimed",
      claimedAt: ev.block.timestamp,
    });
  }
  await bumpOwner(context.db, winner, { prizesWon: 1, totalPrizeWon: amount });
  await bumpGlobal(context.db, { prizeFund: -amount, lastBlock: ev.block.number });
  await logEvent(context.db, ev, "PrizeClaimed", { actor: winner, amount });
});

ponder.on("SatoStonesVault:PrizeDrawRecovered", async ({ event: ev, context }) => {
  const { requestId, amount } = ev.args;
  const rows = await context.db.sql
    .select()
    .from(draw)
    .where(eq(draw.vrfRequestId, requestId))
    .limit(1);
  const found = rows[0];
  if (found) {
    await context.db.update(draw, { drawId: found.drawId }).set({
      status: "recovered",
      recoveredAt: ev.block.timestamp,
    });
  }
  await logEvent(context.db, ev, "PrizeDrawRecovered", {
    amount,
    extra: { vrfRequestId: requestId.toString() },
  });
});

ponder.on("SatoStonesVault:DevWithdrawn", async ({ event: ev, context }) => {
  await logEvent(context.db, ev, "DevWithdrawn", {
    actor: ev.args.to,
    amount: ev.args.amount,
  });
  await bumpGlobal(context.db, { devBalance: -ev.args.amount, lastBlock: ev.block.number });
});

// ERC721 Transfer — track ownership transfers (skipping mint Transfer, which we already get via StoneMinted).
ponder.on("SatoStonesVault:Transfer", async ({ event: ev, context }) => {
  const { from, to, tokenId } = ev.args;
  if (from.toLowerCase() === ZERO_ADDR) return; // mint
  if (to.toLowerCase() === ZERO_ADDR) return; // burn — handled by EarlyExit/Redeemed
  const cur = await context.db.find(stone, { tokenId });
  if (cur && cur.owner.toLowerCase() === from.toLowerCase()) {
    await context.db.update(stone, { tokenId }).set({ owner: to });
    if (!cur.exited && !cur.redeemed) {
      await bumpOwner(context.db, from, { stonesActive: -1, totalLocked: -cur.satoLocked });
      await bumpOwner(context.db, to, { stonesActive: 1, totalLocked: cur.satoLocked });
    }
  }
  await logEvent(context.db, ev, "Transfer", {
    tokenId,
    actor: to,
    extra: { from, to },
  });
});
