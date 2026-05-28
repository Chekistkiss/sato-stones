// Your Stones grid — owner-side, multicall-batched.

import { state, RARITY } from "./state.js";
import { $, formatSato } from "./format.js";
import { multicallVault } from "./multicall.js";
import { showTxStatus } from "./tx-status.js";
import { parseVaultError } from "./errors.js";
import { tryIndexer, fetchOwnerStones, indexerEnabled } from "./indexer.js";

let refetchHook = async () => {};

export function bindStonesRefetch(fn) { refetchHook = fn; }

let lastTokenIdsKey = "";

function renderStones(rows) {
  const grid = $("stonesGrid");
  if (!grid) return;
  const myIds = rows.map((r) => Number(r.tokenId));
  const key = myIds.join(",");
  if (key === lastTokenIdsKey && grid.children.length === myIds.length) {
    state.userTokenIds = myIds;
    return;
  }
  lastTokenIdsKey = key;
  state.userTokenIds = myIds;

  if (myIds.length === 0) {
    grid.innerHTML = '<p class="placeholder-msg">No Stones yet. Mint one above.</p>';
    return;
  }

  const prev = new Set(
    [...grid.querySelectorAll("[data-token-id]")].map((el) => Number(el.dataset.tokenId))
  );

  grid.innerHTML = "";
  const nowSec = Date.now() / 1000;
  rows.forEach((r) => {
    const id = Number(r.tokenId);
    const lockEnd = Number(r.lockEnd);
    const locked = BigInt(r.satoLocked) > 0n;
    const lockActive = locked && nowSec < lockEnd;
    const canRedeem = locked && nowSec >= lockEnd;
    const card = document.createElement("div");
    card.className = "stone-card";
    card.dataset.tokenId = String(id);
    if (!prev.has(id)) card.classList.add("stone-settle");

    const actions = lockActive
      ? `<br><button class="btn-outline-pill" data-action="early-exit" data-id="${id}">Early exit</button>`
      : canRedeem
        ? `<br><button class="btn-primary-pill" data-action="redeem" data-id="${id}">Redeem</button>`
        : "";

    const status = locked
      ? `<br><span class="stone-burned">Locked until ${new Date(lockEnd * 1000).toLocaleString()}</span>`
      : `<br><span class="stone-burned">${r.exited ? "Burned" : "Redeemed"}</span>`;

    card.innerHTML = `
      <span class="stone-num">#${id}</span>
      <span class="stone-tier">${RARITY[Number(r.rarity)]}</span>
      <div class="stone-burned">Peak: ${formatSato(BigInt(r.peakSato))} SATO</div>
      ${status}
      ${actions}
    `;
    grid.appendChild(card);
  });
}

export async function fetchUserStones() {
  const grid = $("stonesGrid");
  if (!grid || !state.userAddress || !state.vault) return;

  $("stonesDisconnected")?.classList.add("hidden");
  grid.classList.remove("hidden");

  // 1) Try indexer first when configured. It returns canonical per-owner rows.
  if (indexerEnabled()) {
    const data = await tryIndexer(fetchOwnerStones, state.userAddress);
    if (data && Array.isArray(data.stones)) {
      // Filter to truly active stones; redeemed/exited ones still render with status.
      renderStones(data.stones);
      return;
    }
  }

  // 2) Fallback: multicall sweep across all minted token IDs.
  const total = state.minted;
  if (total === 0) {
    grid.innerHTML = "";
    state.userTokenIds = [];
    return;
  }

  // Batch ownerOf for all ids via Multicall3.
  const ownerCalls = [];
  for (let id = 1; id <= total; id++) {
    ownerCalls.push({ method: "ownerOf", args: [id], allowFailure: true });
  }
  let owners;
  try {
    owners = await multicallVault(state.vault.runner.provider, ownerCalls);
  } catch {
    // fallback: skip multicall path, leave grid empty rather than thrash RPC
    grid.innerHTML = '<p class="placeholder-msg">Could not load Stones right now.</p>';
    return;
  }
  const myIds = [];
  const me = state.userAddress.toLowerCase();
  for (let i = 0; i < owners.length; i++) {
    const o = owners[i];
    if (o && String(o).toLowerCase() === me) myIds.push(i + 1);
  }

  // Batch vaults(id) for owned stones.
  const vCalls = myIds.map((id) => ({ method: "vaults", args: [id] }));
  const vaults = myIds.length
    ? await multicallVault(state.vault.runner.provider, vCalls)
    : [];

  const rows = myIds.map((id, i) => ({
    tokenId: id,
    peakSato: vaults[i].peakSato,
    satoLocked: vaults[i].satoLocked,
    lockEnd: vaults[i].lockEnd,
    rarity: vaults[i].rarity,
    exited: false,
    redeemed: vaults[i].satoLocked === 0n,
  }));
  renderStones(rows);
}

export async function redeemStone(id) {
  try {
    showTxStatus({ title: "Redeem", message: "Confirm redeem in wallet…", hint: "" }, "pending");
    const tx = await state.vault.redeem(id);
    await tx.wait();
    showTxStatus({ title: "Redeemed", message: "SATO returned. NFT kept.", hint: "" }, "success");
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

export async function earlyExitStone(id) {
  try {
    const [penalty, v] = await Promise.all([
      state.vault.getEarlyExitPenalty(id),
      state.vault.vaults(id),
    ]);
    const returned = v.satoLocked > penalty ? v.satoLocked - penalty : 0n;
    const ok = window.confirm(
      "Early exit burns Stone #" + id +
      "\n\nPenalty ≈ " + formatSato(penalty) + " SATO" +
      "\nReturned ≈ " + formatSato(returned) + " SATO\n\nContinue?"
    );
    if (!ok) return;
    showTxStatus({ title: "Early exit", message: "Confirm early exit in wallet…", hint: "" }, "pending");
    const tx = await state.vault.earlyExit(id);
    await tx.wait();
    showTxStatus({ title: "Early exit", message: "Penalty applied. NFT burned.", hint: "" }, "success");
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}
