// Mint panel: deposit input, lock segment, approve + mint.

import { CONFIG, state, RARITY } from "./state.js";
import { $, setText, formatSato } from "./format.js";
import { restartAnimation, pulse } from "./animate.js";
import { showTxStatus } from "./tx-status.js";
import { parseVaultError } from "./errors.js";

let refetchHook = async () => {};

export function bindMintRefetch(fn) { refetchHook = fn; }

export function initMint() {
  $("mintGross")?.addEventListener("input", () => updateMintUI());
  initLockSegment();
}

function initLockSegment() {
  const seg = $("mintLockSegment");
  if (!seg) return;
  seg.addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-lock]");
    if (!btn) return;
    const lock = btn.dataset.lock;
    [...seg.querySelectorAll("button")].forEach((b) => {
      b.setAttribute("aria-pressed", b === btn ? "true" : "false");
    });
    const hidden = $("mintLock");
    if (hidden) hidden.value = lock;
    updateMintUI();
  });
}

function getLockValue() {
  const seg = $("mintLockSegment");
  if (seg) {
    const pressed = seg.querySelector('button[aria-pressed="true"]');
    if (pressed) return Number(pressed.dataset.lock || 0);
  }
  return Number($("mintLock")?.value || 0);
}

export async function updateMintUI() {
  const nonce = ++state.mintUiNonce;
  const ethers = globalThis.ethers;
  const grossInput = Number($("mintGross")?.value || 100);
  const lock = getLockValue();
  const summary = $("mintSummary");
  const approveBtn = $("approveBtn");
  const mintBtn = $("mintBtn");

  updateMintMotion(lock);
  if (approveBtn) approveBtn.disabled = !state.signer;
  if (mintBtn) mintBtn.disabled = !state.signer;

  if (summary) {
    summary.textContent = `Gross: ${grossInput} SATO · Lock: ${[15, 30, 60][lock]}d · One reward season`;
    restartAnimation(summary, "motion-pop");
  }
  setText("mintStoneNum", "#" + (state.minted + 1));

  if (!state.signer || !state.vault || !state.sato || !ethers) return;

  try {
    const grossWei = ethers.parseUnits(String(grossInput || 0), state.satoDecimals);
    const [bal, allowance, mintedByWallet, maxPerWallet, maxGross, preview] = await Promise.all([
      state.sato.balanceOf(state.userAddress),
      state.sato.allowance(state.userAddress, CONFIG.contractAddress),
      state.vault.walletMintCount(state.userAddress),
      state.vault.MAX_MINTS_PER_WALLET(),
      state.vault.maxGrossForMint(),
      state.vault.previewMint(grossWei, lock),
    ]);
    if (nonce !== state.mintUiNonce) return;

    setText("mintSatoBal", formatSato(bal));
    const issues = [];
    if (grossWei < ethers.parseUnits("100", state.satoDecimals)) issues.push("minimum deposit is 100 SATO");
    if (grossWei > maxGross) issues.push("deposit exceeds current cap of " + formatSato(maxGross) + " SATO");
    if (bal < grossWei) issues.push("insufficient SATO balance");
    if (mintedByWallet >= maxPerWallet) issues.push("wallet mint limit reached");

    const approved = allowance >= grossWei;
    if (summary) {
      summary.textContent = `Peak: ${formatSato(preview.peakSato)} SATO · Weight: ${preview.weight.toString()} · Rarity: ${RARITY[Number(preview.rarity)]}`;
      restartAnimation(summary, "motion-pop");
    }
    if (approveBtn) {
      approveBtn.disabled = issues.length > 0 || approved;
      approveBtn.title = approved ? "Allowance is already sufficient" : issues.join("; ");
    }
    if (mintBtn) {
      mintBtn.disabled = issues.length > 0 || !approved;
      mintBtn.title = issues.length ? issues.join("; ") : approved ? "" : "Approve SATO first";
    }
  } catch (err) {
    if (summary) summary.textContent = "Enter a valid deposit amount.";
    if (approveBtn) approveBtn.disabled = true;
    if (mintBtn) mintBtn.disabled = true;
  }
}

function updateMintMotion(lock) {
  const box = $("mintBox");
  if (!box) return;
  box.dataset.lock = ["15", "30", "60"][lock] || "15";
  restartAnimation(box, "mint-shift");
}

export async function approveSato() {
  if (!state.sato) return;
  try {
    showTxStatus({ title: "Approve", message: "Confirm SATO approval in wallet…", hint: "" }, "pending");
    const tx = await state.sato.approve(CONFIG.contractAddress, globalThis.ethers.MaxUint256);
    await tx.wait();
    showTxStatus({ title: "Approved", message: "SATO approved.", hint: "" }, "success");
    await updateMintUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

export async function mintVault() {
  if (!state.signer || !state.vault) return;
  const ethers = globalThis.ethers;
  const gross = ethers.parseUnits($("mintGross").value, state.satoDecimals);
  const lock = getLockValue();
  showTxStatus({ title: "Mint", message: "Confirm vault mint in wallet…", hint: "" }, "pending");
  try {
    const tx = await state.vault.mint(gross, lock);
    await tx.wait();
    showTxStatus({ title: "Minted", message: "Stone settled. Check Your Stones.", hint: "" }, "success");
    pulse($("statMinted"));
    await refetchHook();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}
