// Reward season panel: status, chunked finalize, lazy claims.

import { state } from "./state.js";
import { $, formatSato } from "./format.js";
import { multicallVault } from "./multicall.js";
import { showTxStatus } from "./tx-status.js";
import { parseVaultError } from "./errors.js";

let refetchHook = async () => {};
export function bindSeasonRefetch(fn) { refetchHook = fn; }

export async function updateSeasonUI() {
  const status = $("seasonStatus");
  const finalizeBtn = $("finalizeSeasonBtn");
  const recoverBtn = $("recoverPrizeBtn");
  const claims = $("seasonClaims");
  if (!status || !finalizeBtn || !recoverBtn || !claims) return;

  finalizeBtn.classList.add("hidden");
  recoverBtn.classList.add("hidden");
  claims.classList.add("hidden");
  claims.innerHTML = "";

  if (!state.signer || !state.vault) {
    status.textContent = "Connect wallet to finalize the reward season and claim rewards.";
    return;
  }

  const provider = state.vault.runner.provider;
  const [
    isFinalized,
    seasonInProgress,
    processedUntil,
    t0,
    seasonDuration,
    pendingPrize,
    pendingRequestId,
    lastPrizeDrawAt,
    prizeDrawTimeout,
  ] = await multicallVault(provider, [
    { method: "seasonFinalized", args: [0] },
    { method: "seasonSnapshotStarted" },
    { method: "seasonProcessedUntil" },
    { method: "t0" },
    { method: "SEASON_DURATION" },
    { method: "pendingDrawPrize" },
    { method: "pendingDrawRequestId" },
    { method: "lastPrizeDrawAt" },
    { method: "PRIZE_DRAW_TIMEOUT" },
  ]);

  const seasonEnd = Number(t0) + Number(seasonDuration);
  const nowSec = Math.floor(Date.now() / 1000);
  const drawRequestedAt = Number(lastPrizeDrawAt);
  const drawTimeout = Number(prizeDrawTimeout);

  if (!isFinalized) {
    if (nowSec >= seasonEnd) {
      status.textContent = seasonInProgress
        ? `Reward season finalization in progress. Processed up to #${processedUntil.toString()}.`
        : "Reward season ended. Finalize in chunks to open claims.";
      finalizeBtn.textContent = seasonInProgress ? "Continue finalization" : "Start finalization";
      finalizeBtn.dataset.seasonId = "0";
      finalizeBtn.classList.remove("hidden");
    } else {
      status.textContent = `Reward season active. Finalize after ${new Date(seasonEnd * 1000).toLocaleString()}.`;
    }
  } else {
    status.textContent = "Reward season is finalized. Claim available rewards below.";
  }

  if (pendingPrize > 0n && pendingRequestId > 0n && nowSec >= drawRequestedAt + drawTimeout) {
    recoverBtn.textContent = `Recover timed-out draw #${pendingRequestId.toString()}`;
    recoverBtn.classList.remove("hidden");
  } else if (pendingPrize > 0n && pendingRequestId > 0n) {
    status.textContent += ` · Prize draw #${pendingRequestId.toString()} waiting for VRF.`;
  }

  if (!isFinalized || state.userTokenIds.length === 0) return;

  // Multicall claimable amounts + claimed flag for owned tokens.
  const calls = [];
  for (const id of state.userTokenIds) {
    calls.push({ method: "snapshotOwner", args: [0, id] });
    calls.push({ method: "claimableSeasonAmount", args: [0, id] });
    calls.push({ method: "seasonClaimed", args: [0, id] });
  }
  const results = await multicallVault(provider, calls);

  const rows = [];
  for (let i = 0; i < state.userTokenIds.length; i++) {
    const id = state.userTokenIds[i];
    const owner = results[i * 3];
    const amount = results[i * 3 + 1];
    const claimed = results[i * 3 + 2];
    if (!owner || owner.toLowerCase() !== state.userAddress.toLowerCase()) continue;
    if (!amount || amount === 0n || claimed) continue;
    rows.push({ tokenId: id, amount });
  }

  for (const row of rows) {
    const card = document.createElement("div");
    card.className = "stone-card";
    card.innerHTML = `
      <strong>Reward season</strong><br>
      Stone #${row.tokenId}<br>
      Claim: ${formatSato(row.amount)} SATO<br>
      <button class="btn-primary-pill" data-action="claim-season" data-id="${row.tokenId}">Claim</button>
    `;
    claims.appendChild(card);
  }
  if (rows.length > 0) claims.classList.remove("hidden");
}

export async function finalizeSeasonById(seasonId = 0) {
  try {
    showTxStatus({ title: "Finalize season", message: "Confirm chunked finalization in wallet…", hint: "Several txs may be needed for a full collection." }, "pending");
    const tx = await state.vault.processSeasonSnapshot(seasonId, 150);
    await tx.wait();
    const done = await state.vault.seasonFinalized(seasonId);
    showTxStatus(
      { title: done ? "Season finalized" : "Progress saved", message: done ? "Rewards are ready to claim." : "Run Continue finalization until complete.", hint: "" },
      done ? "success" : "pending"
    );
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

export async function claimSeasonReward(tokenId) {
  try {
    showTxStatus({ title: "Claim season", message: "Confirm claim in wallet…", hint: "" }, "pending");
    const tx = await state.vault.claimSeason(0, tokenId);
    await tx.wait();
    showTxStatus({ title: "Season claimed", message: "SATO reward received.", hint: "" }, "success");
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

export async function recoverPrizeDraw() {
  try {
    showTxStatus({ title: "Recover draw", message: "Confirm recovery in wallet…", hint: "" }, "pending");
    const tx = await state.vault.recoverTimedOutPrizeDraw();
    await tx.wait();
    showTxStatus({ title: "Prize recovered", message: "Pending prize returned to prize fund.", hint: "" }, "success");
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}
