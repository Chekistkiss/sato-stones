// Prize draw / lottery panel.

import { state } from "./state.js";
import { $, formatSato } from "./format.js";
import { multicallVault } from "./multicall.js";
import { showTxStatus } from "./tx-status.js";
import { parseVaultError } from "./errors.js";

let refetchHook = async () => {};
export function bindLotteryRefetch(fn) { refetchHook = fn; }

export async function updateLotteryUI() {
  const el = $("lotteryHistory");
  if (!el) return;
  if (!state.vault) {
    el.innerHTML = '<p class="placeholder-msg">Connect wallet to request draws and claim prizes.</p>';
    return;
  }

  const provider = state.vault.runner.provider;
  const [prizeFund, canRequest, pendingPrize, pendingRequestId, userPrize, snapshotStarted, snapshotNextTokenId] =
    await multicallVault(provider, [
      { method: "prizeFund" },
      { method: "canRequestPrizeDraw" },
      { method: "pendingDrawPrize" },
      { method: "pendingDrawRequestId" },
      { method: "pendingPrize", args: [state.userAddress] },
      { method: "prizeSnapshotStarted" },
      { method: "prizeSnapshotNextTokenId" },
    ]);

  let html = `<p class="placeholder-msg">Prize fund: <strong>${formatSato(prizeFund)} SATO</strong></p>`;
  if (snapshotStarted) {
    html += `<p class="placeholder-msg">Prize snapshot in progress. Next token: #${snapshotNextTokenId.toString()}.</p>`;
    html += `<button class="btn-outline-pill" data-action="continue-prize-snapshot">Continue prize snapshot</button>`;
  } else if (pendingPrize > 0n && pendingRequestId > 0n) {
    html += `<p class="placeholder-msg">Draw #${pendingRequestId.toString()} pending VRF for ${formatSato(pendingPrize)} SATO.</p>`;
  } else if (canRequest) {
    html += `<button class="btn-outline-pill" data-action="request-prize-draw">Start prize draw snapshot</button>`;
  } else {
    html += `<p class="placeholder-msg">Draw not available yet. Pool must reach minimum and interval must pass.</p>`;
  }
  if (userPrize > 0n) {
    html += `<button class="btn-primary-pill" data-action="claim-prize">Claim prize: ${formatSato(userPrize)} SATO</button>`;
  }
  el.innerHTML = html;
}

export async function requestPrizeDraw() {
  try {
    showTxStatus({ title: "Prize draw", message: "Confirm snapshot start in wallet…", hint: "May take several transactions before VRF request." }, "pending");
    const tx = await state.vault.requestPrizeDraw();
    await tx.wait();
    const requestId = await state.vault.pendingDrawRequestId();
    const snapshotStarted = await state.vault.prizeSnapshotStarted();
    showTxStatus(
      {
        title: requestId > 0n ? "Draw requested" : "Snapshot progress saved",
        message: requestId > 0n
          ? "Waiting for VRF fulfillment."
          : snapshotStarted
            ? "Run Continue prize snapshot until complete."
            : "No eligible tickets; prize returned to fund.",
        hint: "",
      },
      requestId > 0n ? "success" : "pending"
    );
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

export async function continuePrizeDrawSnapshot() {
  try {
    showTxStatus({ title: "Prize snapshot", message: "Confirm next snapshot chunk in wallet…", hint: "" }, "pending");
    const tx = await state.vault.processPrizeDrawSnapshot(150);
    await tx.wait();
    const requestId = await state.vault.pendingDrawRequestId();
    const snapshotStarted = await state.vault.prizeSnapshotStarted();
    showTxStatus(
      {
        title: requestId > 0n ? "Draw requested" : "Snapshot progress saved",
        message: requestId > 0n
          ? "Waiting for VRF fulfillment."
          : snapshotStarted
            ? "Run Continue prize snapshot until complete."
            : "No eligible tickets; prize returned to fund.",
        hint: "",
      },
      requestId > 0n ? "success" : "pending"
    );
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

export async function claimPrize() {
  try {
    showTxStatus({ title: "Claim prize", message: "Confirm prize claim in wallet…", hint: "" }, "pending");
    const tx = await state.vault.claimPrize();
    await tx.wait();
    showTxStatus({ title: "Prize claimed", message: "SATO prize received.", hint: "" }, "success");
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}
