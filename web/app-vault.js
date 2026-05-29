// Sato Stones — entry point. ES module.
// Composes per-panel modules. Loads ethers lazily on user intent.

import { CONFIG, state } from "./app/state.js";
import { VAULT_ABI } from "./app/contract.js";
import { loadEthers } from "./app/ethers-loader.js";
import { multicallVault } from "./app/multicall.js";
import { animateDigits, animateCountText, pulse, initScrollReveal, initTierCardTilt } from "./app/animate.js";
import { $, setText, formatSato } from "./app/format.js";
import { showTxStatus } from "./app/tx-status.js";
import { connectWallet, setHooks as setWalletHooks } from "./app/wallet.js";
import { initMint, updateMintUI, approveSato, mintVault, bindMintRefetch } from "./app/mint.js";
import { fetchUserStones, redeemStone, earlyExitStone, bindStonesRefetch } from "./app/stones.js";
import { updateSeasonUI, finalizeSeasonById, claimSeasonReward, recoverPrizeDraw, bindSeasonRefetch } from "./app/season.js";
import { updateLotteryUI, requestPrizeDraw, continuePrizeDrawSnapshot, claimPrize, bindLotteryRefetch } from "./app/lottery.js";
import { initNav, initMobileCta } from "./app/nav.js";
import { tryIndexer, fetchGlobalStats, indexerEnabled } from "./app/indexer.js";

let readProvider = null;
let ctaApi = null;

document.addEventListener("DOMContentLoaded", async () => {
  initNav();
  initScrollReveal();
  updateExplorerLinks();
  initMint();
  initActionDelegation();
  setWalletHooks({
    onConnected: async () => {
      await refetchAll({ stones: true, mint: true, season: true, lottery: true });
      ctaApi?.refresh?.();
    },
    onReset: async () => {
      state.minted = 0;
      state.userTokenIds = [];
      setText("statMinted", "0 / " + CONFIG.maxSupply);
      setText("statPrize", "0 SATO");
      animateDigits($("heroBurnCount"), 0, String);
      await updateLotteryUI();
      ctaApi?.refresh?.();
    },
  });
  bindMintRefetch(() => refetchAll({ stones: true, mint: true }));
  bindStonesRefetch(() => refetchAll({ stones: true, mint: true }));
  bindSeasonRefetch(() => refetchAll({ stones: true, season: true }));
  bindLotteryRefetch(() => refetchAll({ lottery: true, mint: true }));

  ctaApi = initMobileCta({
    onConnect: () => connectWallet(),
    onMint: () => mintVault(),
    onClaim: () => {},
  });

  // Detect demo state.
  state.isDemo = !CONFIG.contractAddress || CONFIG.contractAddress.startsWith("0x000");

  // Read-only fetch on load — only if a contract is configured.
  if (!state.isDemo) {
    const kickoff = async () => {
      try {
        await ensureReadProvider();
        await fetchGlobalRead();
        initTierCardTilt();
      } catch (e) {
        const banner = $("connectivityBanner");
        banner?.classList.remove("hidden");
      }
    };
    const idle = globalThis.requestIdleCallback || ((fn) => setTimeout(fn, 1200));
    idle(() => { kickoff(); }, { timeout: 2500 });
  } else {
    initTierCardTilt();
  }
  await updateMintUI();
});

async function ensureReadProvider() {
  const ethers = await loadEthers();
  if (!readProvider) {
    const rpc = CONFIG.rpcUrls?.[0];
    readProvider = new ethers.JsonRpcProvider(rpc);
  }
  return readProvider;
}

async function fetchGlobalRead() {
  // Indexer-first path: a single HTTP round-trip vs. 4-call RPC multicall.
  if (indexerEnabled()) {
    const stats = await tryIndexer(fetchGlobalStats);
    if (stats) {
      state.previousMinted = state.minted;
      state.minted = Number(stats.totalMinted ?? 0);
      state.season = 0;
      state.prize = BigInt(stats.prizeFund ?? 0);
      state.pool = BigInt(stats.seasonPool ?? 0);
      paintGlobal();
      if (state.minted > state.previousMinted && state.previousMinted > 0) {
        pulse($("statMinted"));
      }
      return;
    }
  }
  await ensureReadProvider();
  state.previousMinted = state.minted;
  const [minted, season, pool, prize] = await multicallVault(readProvider, [
    { method: "totalMintedEver" },
    { method: "currentSeasonId" },
    { method: "seasonPool", args: [0] },
    { method: "prizeFund" },
  ]);
  state.minted = Number(minted);
  state.season = Number(season);
  state.pool = pool;
  state.prize = prize;
  paintGlobal();
}

function paintGlobal() {
  animateCountText($("statMinted"), state.previousMinted, state.minted, (v) => v + " / " + CONFIG.maxSupply);
  setText("statTier", state.season === 0 ? "Reward season" : "Finalized");
  setText("statPrice", "100–10k SATO");
  setText("statPrize", formatSato(state.prize) + " SATO");
  pulse($("statPrize"));
  animateDigits($("heroBurnCount"), state.minted, (v) => String(v));
  setText("heroBurnSecondary", "One reward season");
}

async function refetchAll(parts = {}) {
  try {
    await fetchGlobalRead();
  } catch {}
  if (parts.stones && state.signer) await fetchUserStones();
  if (parts.season && state.signer) await updateSeasonUI();
  if (parts.lottery && state.signer) await updateLotteryUI();
  if (parts.mint) await updateMintUI();
}

function updateExplorerLinks() {
  const base = (CONFIG.explorerBaseUrl || "").replace(/\/$/, "");
  const c = $("contractLink");
  const t = $("tokenLink");
  if (c && CONFIG.contractAddress) c.href = base + "/address/" + CONFIG.contractAddress;
  if (t && CONFIG.satoTokenAddress) t.href = base + "/address/" + CONFIG.satoTokenAddress;
  const close = $("connectivityBannerClose");
  close?.addEventListener("click", () => $("connectivityBanner")?.classList.add("hidden"));
}

// --- event delegation: every actionable button has data-action ---
function initActionDelegation() {
  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-action]");
    if (!t) return;
    const action = t.dataset.action;
    const id = t.dataset.id ? Number(t.dataset.id) : undefined;

    switch (action) {
      case "connect":
        if (!state.signer) connectWallet();
        return;
      case "approve":
        approveSato();
        return;
      case "mint":
        mintVault();
        return;
      case "redeem":
        if (id) redeemStone(id);
        return;
      case "early-exit":
        if (id) earlyExitStone(id);
        return;
      case "finalize-season":
        finalizeSeasonById(0);
        return;
      case "recover-prize":
        recoverPrizeDraw();
        return;
      case "claim-season":
        if (id) claimSeasonReward(id);
        return;
      case "request-prize-draw":
        requestPrizeDraw();
        return;
      case "continue-prize-snapshot":
        continuePrizeDrawSnapshot();
        return;
      case "claim-prize":
        claimPrize();
        return;
    }
  });

  // Wire Connect Wallet nav button (no inline handler).
  document.getElementById("navConnectBtn")?.addEventListener("click", () => connectWallet());
}
