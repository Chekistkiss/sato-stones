/* Sato Stones Vault — MVP frontend (ethers v6) */

const DEFAULT_CONFIG = {
  contractAddress: "0x0000000000000000000000000000000000000000",
  satoTokenAddress: "0x0000000000000000000000000000000000000000",
  chainId: 11155111,
  chainName: "Sepolia",
  rpcUrls: ["https://ethereum-sepolia-rpc.publicnode.com"],
  explorerBaseUrl: "https://sepolia.etherscan.io",
  maxSupply: 2100,
};
const CONFIG = { ...DEFAULT_CONFIG, ...(window.SATO_STONES_CONFIG || {}) };

const VAULT_ABI = [
  "function totalMintedEver() view returns (uint256)",
  "function genesisMintedCount() view returns (uint256)",
  "function genesisFinalized() view returns (bool)",
  "function genesisCandidatesCount() view returns (uint256)",
  "function SEASON_DURATION() view returns (uint256)",
  "function MIN_GROSS() view returns (uint256)",
  "function TRANSFER_LOCKOUT() view returns (uint256)",
  "function timeToTransferLockout() view returns (uint256)",
  "function finalizeGenesis() external",
  "function claimSeasonBatch(uint256 seasonId, uint256[] tokenIds) external",
  "function currentSeasonId() view returns (uint256)",
  "function t0() view returns (uint256)",
  "function SEASON_DURATION() view returns (uint256)",
  "function MAX_MINTS_PER_WALLET() view returns (uint256)",
  "function seasonPool(uint256) view returns (uint256)",
  "function seasonFinalized(uint256) view returns (bool)",
  "function snapshotOwner(uint256,uint256) view returns (address)",
  "function claimAmount(uint256,uint256) view returns (uint256)",
  "function seasonClaimed(uint256,uint256) view returns (bool)",
  "function prizeFund() view returns (uint256)",
  "function pendingDrawPrize() view returns (uint256)",
  "function pendingDrawRequestId() view returns (uint256)",
  "function pendingPrize(address) view returns (uint256)",
  "function PRIZE_DRAW_TIMEOUT() view returns (uint256)",
  "function lastPrizeDrawAt() view returns (uint256)",
  "function prizeDrawInterval() view returns (uint256)",
  "function canRequestPrizeDraw() view returns (bool)",
  "function maxGrossForMint() view returns (uint256)",
  "function walletMintCount(address) view returns (uint256)",
  "function getEarlyExitPenalty(uint256) view returns (uint256)",
  "function mint(uint256 grossAmount, uint8 lockDays) external returns (uint256)",
  "function earlyExit(uint256 tokenId) external",
  "function redeem(uint256 tokenId) external",
  "function finalizeSeason(uint256 seasonId) external",
  "function claimSeason(uint256 seasonId, uint256 tokenId) external",
  "function requestPrizeDraw() external returns (uint256)",
  "function recoverTimedOutPrizeDraw() external",
  "function claimPrize() external",
  "function previewMint(uint256 grossAmount, uint8 lockDays) view returns (uint256 peakSato, uint32 weightWithoutGenesis, uint32 weightIfGenesis, uint8 rarityWithoutGenesis, uint8 rarityIfGenesis, uint256 estGenesisScore, bool genesisRaceOpen)",
  "function vaults(uint256) view returns (uint256 peakSato, uint256 satoLocked, uint64 mintTime, uint64 lockEnd, uint32 weightAtMint, uint8 lockDays, uint8 rarity, bool isGenesis, uint8 genesisRank, bool redeemed)",
  "function ownerOf(uint256) view returns (address)",
  "function balanceOf(address) view returns (uint256)",
  "error MintedOut()",
  "error ExceedsWalletMintLimit()",
  "error DepositTooLow()",
  "error DepositTooHigh()",
  "error NotTokenOwner()",
  "error LockEndedUseRedeem()",
  "error LockNotEnded()",
  "error VaultEmpty()",
  "error SeasonNotEnded()",
  "error SeasonAlreadyFinalized()",
  "error SeasonNotFinalized()",
  "error NothingToClaim()",
  "error AlreadyClaimed()",
  "error NotSnapshotOwner()",
  "error SeasonTransferLocked()",
  "error PrizePoolTooLow()",
  "error PrizeDrawTooSoon()",
  "error NoPendingPrize()",
  "error OnlyVRFCoordinator()",
  "error InvalidDrawRequest()",
  "error DrawPending()",
  "error NoEligibleTickets()",
  "error PrizeDrawNotTimedOut()",
  "event StoneMinted(address indexed minter, uint256 indexed tokenId, uint256 grossSato, uint256 peakSato, uint8 lockDays, uint32 weightAtMint, uint64 mintTime, uint64 lockEnd)",
];
let vaultIface;

const SATO_ABI = [
  "function approve(address,uint256) returns (bool)",
  "function allowance(address,address) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

const LOCK = { Thirty: 0, Ninety: 1, OneEighty: 2, ThreeSixtyFive: 3 };
const RARITY = ["Common", "Uncommon", "Rare", "Mythic"];

let provider, signer, userAddress, vault, sato, satoDecimals = 18;
let isDemo = true;
let walletListenersInstalled = false;
let mintUiNonce = 0;

const state = { minted: 0, genesis: 0, season: 0, pool: 0n, prize: 0n, userTokenIds: [] };

function applyV2MintForm() {
  const lockSel = document.getElementById("mintLock");
  if (lockSel) {
    lockSel.innerHTML = '<option value="0">30 days</option><option value="1">90 days</option><option value="2" selected>180 days</option><option value="3">365 days</option>';
  }
  const gross = document.getElementById("mintGross");
  if (gross) { gross.min = "50"; gross.value = "500"; }
  const info = document.querySelector("#mint .mint-info:last-of-type");
  if (info) info.textContent = "V2: 4% mint fee (pool/dev/prize/burn). Genesis = top-21 by commitment in first 30 days.";
}

document.addEventListener("DOMContentLoaded", async () => {
  applyV2MintForm();
  initIntroAnimation();
  initScrollNav();
  initMobileNav();
  initScrollReveal();
  updateExplorerLinks();
  if (!(await waitForEthers(5000))) return;
  isDemo = !CONFIG.contractAddress || CONFIG.contractAddress.startsWith("0x000");
  if (!isDemo) await fetchGlobal();
  updateMintUI();
});

function waitForEthers(ms) {
  return new Promise((r) => {
    if (window.ethers) return r(true);
    const t = setTimeout(() => r(!!window.ethers), ms);
    const i = setInterval(() => {
      if (window.ethers) {
        clearInterval(i);
        clearTimeout(t);
        r(true);
      }
    }, 100);
  });
}

async function connectWallet() {
  if (!window.ethereum) {
    showTxStatus({ title: "No wallet", message: "Install MetaMask.", hint: "" }, "error");
    return;
  }
  provider = new ethers.BrowserProvider(window.ethereum);
  if (!(await ensureConfiguredNetwork())) return;
  installWalletListeners();
  signer = await provider.getSigner();
  userAddress = await signer.getAddress();
  vault = new ethers.Contract(CONFIG.contractAddress, VAULT_ABI, signer);
  sato = new ethers.Contract(CONFIG.satoTokenAddress, SATO_ABI, signer);
  satoDecimals = Number(await sato.decimals());

  document.getElementById("mintDisconnected").classList.add("hidden");
  document.getElementById("mintConnected").classList.remove("hidden");
  document.getElementById("mintAddr").textContent = short(userAddress);
  document.getElementById("navConnectBtn").textContent = short(userAddress);

  await fetchGlobal();
  await fetchUserStones();
  await updateSeasonUI();
  await updateLotteryUI();
  updateMintUI();
}

async function ensureConfiguredNetwork() {
  const net = await provider.getNetwork();
  if (Number(net.chainId) === CONFIG.chainId) return true;

  const chainIdHex = "0x" + CONFIG.chainId.toString(16);
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: chainIdHex }],
    });
    provider = new ethers.BrowserProvider(window.ethereum);
    return true;
  } catch (err) {
    if (err?.code === 4902) {
      try {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: chainIdHex,
            chainName: CONFIG.chainName,
            rpcUrls: CONFIG.rpcUrls,
            blockExplorerUrls: CONFIG.explorerBaseUrl ? [CONFIG.explorerBaseUrl] : undefined,
            nativeCurrency: CONFIG.nativeCurrency || { name: "Ether", symbol: "ETH", decimals: 18 },
          }],
        });
        provider = new ethers.BrowserProvider(window.ethereum);
        return true;
      } catch (addErr) {
        showTxStatus(parseVaultError(addErr), "error");
        return false;
      }
    }
    showTxStatus({ title: "Wrong network", message: "Switch to " + CONFIG.chainName, hint: "" }, "error");
    return false;
  }
}

function installWalletListeners() {
  if (walletListenersInstalled || !window.ethereum?.on) return;
  walletListenersInstalled = true;
  window.ethereum.on("accountsChanged", () => resetWalletState("Wallet account changed. Reconnect to continue."));
  window.ethereum.on("chainChanged", () => resetWalletState("Network changed. Reconnect on " + CONFIG.chainName + "."));
}

function resetWalletState(message) {
  provider = signer = vault = sato = null;
  userAddress = null;
  state.userTokenIds = [];
  document.getElementById("mintDisconnected")?.classList.remove("hidden");
  document.getElementById("mintConnected")?.classList.add("hidden");
  setText("navConnectBtn", "Connect Wallet");
  setText("stonesDisconnected", "Connect wallet to view your stones.");
  document.getElementById("stonesDisconnected")?.classList.remove("hidden");
  document.getElementById("stonesGrid")?.classList.add("hidden");
  updateLotteryUI();
  showTxStatus({ title: "Wallet changed", message, hint: "" }, "error");
}

function getReadProvider() {
  const rpc = CONFIG.rpcUrls?.[0] || DEFAULT_CONFIG.rpcUrls[0];
  return new ethers.JsonRpcProvider(rpc);
}

async function fetchGlobal() {
  const v = new ethers.Contract(CONFIG.contractAddress, VAULT_ABI, getReadProvider());
  const previousMinted = state.minted;
  const previousGenesis = state.genesis;
  state.minted = Number(await v.totalMintedEver());
  state.genesis = Number(await v.genesisMintedCount());
  const season = Number(await v.currentSeasonId());
  const pool = await v.seasonPool(season);
  const prize = await v.prizeFund();
  state.season = season;
  state.pool = pool;
  state.prize = prize;

  animateCountText("statMinted", previousMinted, state.minted, (value) => value + " / " + CONFIG.maxSupply);
  setText("statTier", "Season " + season);
  setText("statPrice", "Vault lock");
  setText("statPrize", formatSato(prize) + " SATO");
  pulseText("statPrize");
  animateCountText("heroBurnCount", previousMinted, state.minted, (value) => String(value));
  animateCountText("heroBurnSecondary", previousGenesis, state.genesis, (value) => value + " / 21 Genesis (finalized leaderboard)");
}

async function updateMintUI() {
  const nonce = ++mintUiNonce;
  const gross = Number(document.getElementById("mintGross")?.value || 100);
  const lock = Number(document.getElementById("mintLock")?.value || 0);
  const summary = document.getElementById("mintSummary");
  const approveBtn = document.getElementById("approveBtn");
  const mintBtn = document.getElementById("mintBtn");
  updateMintMotion(lock);
  if (approveBtn) approveBtn.disabled = !signer;
  if (mintBtn) mintBtn.disabled = !signer;
  if (summary) {
    summary.textContent =
      "Gross: " + gross + " SATO | Lock: " + [30, 90, 180, 365][lock] + "d | Genesis race: top-21 by score (day 30)";
    restartAnimation(summary, "motion-pop");
  }
  setText("mintStoneNum", "#" + (state.minted + 1));
  if (!signer || !vault || !sato) return;

  try {
    const grossWei = ethers.parseUnits(String(gross || 0), satoDecimals);
    const [bal, allowance, mintedByWallet, maxPerWallet, maxGross, preview] = await Promise.all([
      sato.balanceOf(userAddress),
      sato.allowance(userAddress, CONFIG.contractAddress),
      vault.walletMintCount(userAddress),
      vault.MAX_MINTS_PER_WALLET(),
      vault.maxGrossForMint(),
      vault.previewMint(grossWei, lock),
    ]);
    if (nonce !== mintUiNonce) return;

    setText("mintSatoBal", formatSato(bal));
    const issues = [];
    if (grossWei < ethers.parseUnits("50", satoDecimals)) issues.push("minimum deposit is 50 SATO");
    if (grossWei > maxGross) issues.push("deposit exceeds current cap of " + formatSato(maxGross) + " SATO");
    if (bal < grossWei) issues.push("insufficient SATO balance");
    if (mintedByWallet >= maxPerWallet) issues.push("wallet mint limit reached");

    const approved = allowance >= grossWei;
    if (summary) {
      summary.textContent =
        "Peak: " + formatSato(preview.peakSato) +
        " SATO | Weight: " + preview.weightIfGenesis.toString() +
        " (now) / " + preview.weightWithoutGenesis.toString() +
        " | Rarity: " + RARITY[Number(preview.rarityIfGenesis)] +
        (preview.genesisRaceOpen ? " | Genesis race open" : " | Genesis race ended");
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

async function approveSato() {
  const gross = document.getElementById("mintGross").value;
  const tx = await sato.approve(CONFIG.contractAddress, ethers.MaxUint256);
  await tx.wait();
  showTxStatus({ title: "Approved", message: "SATO approved.", hint: "" }, "success");
}

async function mintVault() {
  if (!signer) return;
  const gross = ethers.parseUnits(document.getElementById("mintGross").value, satoDecimals);
  const lock = Number(document.getElementById("mintLock").value);
  showTxStatus({ title: "Mint", message: "Confirm vault mint in wallet…", hint: "" }, "pending");
  try {
    const tx = await vault.mint(gross, lock);
    const r = await tx.wait();
    showTxStatus({ title: "Minted", message: "Stone locked. Check Your Stones.", hint: "" }, "success");
    await fetchGlobal();
    await fetchUserStones();
    await updateSeasonUI();
    await updateLotteryUI();
    await updateMintUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

async function fetchUserStones() {
  const grid = document.getElementById("stonesGrid");
  if (!userAddress || !vault) return;
  grid.innerHTML = "";
  state.userTokenIds = [];
  grid.classList.remove("hidden");
  document.getElementById("stonesDisconnected").classList.add("hidden");

  // tokenIds are #1..#2100 (see _startTokenId in contract)
  for (let id = 1; id <= state.minted; id++) {
    let owner;
    try {
      owner = await vault.ownerOf(id);
    } catch {
      continue;
    }
    if (owner.toLowerCase() !== userAddress.toLowerCase()) continue;
    state.userTokenIds.push(id);
    const v = await vault.vaults(id);
    const card = document.createElement("div");
    card.className = "stone-card";
    const lockEnd = Number(v.lockEnd);
    const locked = v.satoLocked > 0n;
    const nowSec = Date.now() / 1000;
    const lockActive = locked && nowSec < lockEnd;
    const canRedeem = locked && nowSec >= lockEnd;
    let actions = "";
    if (lockActive) {
      actions = '<br><button onclick="earlyExitStone(' + id + ')">Early exit</button>';
    } else if (canRedeem) {
      actions = '<br><button onclick="redeemStone(' + id + ')">Redeem</button>';
    }
    card.innerHTML =
      "<strong>#" +
      id +
      "</strong> " +
      (v.isGenesis ? "Genesis " + Number(v.genesisRank) : RARITY[Number(v.rarity)]) +
      "<br>Peak: " +
      formatSato(v.peakSato) +
      " SATO" +
      (locked ? "<br>Locked until " + new Date(lockEnd * 1000).toLocaleString() : "<br>Redeemed") +
      actions;
    grid.appendChild(card);
  }
}

async function redeemStone(id) {
  try {
    const tx = await vault.redeem(id);
    await tx.wait();
    showTxStatus({ title: "Redeemed", message: "SATO returned. NFT kept.", hint: "" }, "success");
    await fetchUserStones();
    await updateSeasonUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

async function earlyExitStone(id) {
  try {
    const [penalty, v] = await Promise.all([vault.getEarlyExitPenalty(id), vault.vaults(id)]);
    const returned = v.satoLocked > penalty ? v.satoLocked - penalty : 0n;
    const ok = window.confirm(
      "Early exit burns Stone #" + id +
      " and applies an estimated penalty of " + formatSato(penalty) +
      " SATO. Estimated return: " + formatSato(returned) + " SATO.\n\nContinue?"
    );
    if (!ok) return;
    const tx = await vault.earlyExit(id);
    await tx.wait();
    showTxStatus({ title: "Early exit", message: "Penalty applied. NFT burned.", hint: "" }, "success");
    await fetchGlobal();
    await fetchUserStones();
    await updateSeasonUI();
    await updateLotteryUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

async function updateSeasonUI() {
  const status = document.getElementById("seasonStatus");
  const finalizeBtn = document.getElementById("finalizeSeasonBtn");
  const recoverBtn = document.getElementById("recoverPrizeBtn");
  const claims = document.getElementById("seasonClaims");
  if (!status || !finalizeBtn || !recoverBtn || !claims) return;

  finalizeBtn.classList.add("hidden");
  recoverBtn.classList.add("hidden");
  claims.classList.add("hidden");
  claims.innerHTML = "";

  if (!signer || !vault) {
    status.textContent = "Connect wallet to finalize seasons and claim rewards.";
    return;
  }

  const currentSeason = Number(await vault.currentSeasonId());
  const pendingPrize = await vault.pendingDrawPrize();
  const pendingRequestId = await vault.pendingDrawRequestId();
  const drawRequestedAt = Number(await vault.lastPrizeDrawAt());
  const drawTimeout = Number(await vault.PRIZE_DRAW_TIMEOUT());
  const unfinalizedEndedSeasons = [];

  if (currentSeason === 0) {
    status.textContent = "Season 0 is active. Rewards can be finalized after the first season ends.";
  } else {
    for (let seasonId = 0; seasonId < currentSeason; seasonId++) {
      if (!(await vault.seasonFinalized(seasonId))) {
        unfinalizedEndedSeasons.push(seasonId);
      }
    }
    if (unfinalizedEndedSeasons.length > 0) {
      const nextSeason = unfinalizedEndedSeasons[0];
      status.textContent =
        "Season " + nextSeason + " ended and can be finalized. " +
        unfinalizedEndedSeasons.length + " ended season(s) pending.";
      finalizeBtn.textContent = "Finalize season " + nextSeason;
      finalizeBtn.dataset.seasonId = String(nextSeason);
      finalizeBtn.classList.remove("hidden");
    } else {
      status.textContent = "All ended seasons are finalized. Claim available rewards below.";
    }
  }

  if (pendingPrize > 0n && pendingRequestId > 0n && Date.now() / 1000 >= drawRequestedAt + drawTimeout) {
    recoverBtn.textContent = "Recover timed-out draw #" + pendingRequestId.toString();
    recoverBtn.classList.remove("hidden");
  } else if (pendingPrize > 0n && pendingRequestId > 0n) {
    status.textContent += " Prize draw #" + pendingRequestId.toString() + " is waiting for VRF.";
  }

  const rows = [];
  for (const seasonId of unfinalizedEndedSeasons.slice(1)) {
    rows.push({ kind: "finalize", seasonId });
  }
  for (let seasonId = 0; seasonId <= currentSeason; seasonId++) {
    if (!(await vault.seasonFinalized(seasonId))) continue;
    for (let tokenId = 1; tokenId <= state.minted; tokenId++) {
      const ownerAtSnapshot = await vault.snapshotOwner(seasonId, tokenId);
      if (ownerAtSnapshot.toLowerCase() !== userAddress.toLowerCase()) continue;
      const amount = await vault.claimAmount(seasonId, tokenId);
      const claimed = await vault.seasonClaimed(seasonId, tokenId);
      if (amount === 0n || claimed) continue;
      rows.push({ seasonId, tokenId, amount });
    }
  }

  for (const row of rows) {
    const card = document.createElement("div");
    card.className = "stone-card";
    if (row.kind === "finalize") {
      card.innerHTML =
        "<strong>Season " +
        row.seasonId +
        '</strong><br>Ready to finalize<br><button onclick="finalizeSeasonById(' +
        row.seasonId +
        ')">Finalize</button>';
    } else {
      card.innerHTML =
        "<strong>Season " +
        row.seasonId +
        "</strong><br>Stone #" +
        row.tokenId +
        "<br>Claim: " +
        formatSato(row.amount) +
        ' SATO<br><button onclick="claimSeasonReward(' +
        row.seasonId +
        "," +
        row.tokenId +
        ')">Claim</button>';
    }
    claims.appendChild(card);
  }

  if (rows.length > 0) {
    claims.classList.remove("hidden");
  }
}

async function finalizePreviousSeason() {
  try {
    const btn = document.getElementById("finalizeSeasonBtn");
    const seasonId = Number(btn?.dataset.seasonId || 0);
    await finalizeSeasonById(seasonId);
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

async function finalizeSeasonById(seasonId) {
  try {
    showTxStatus({ title: "Finalize season", message: "Confirm finalizeSeason in wallet…", hint: "" }, "pending");
    const tx = await vault.finalizeSeason(seasonId);
    await tx.wait();
    showTxStatus({ title: "Season finalized", message: "Rewards are ready to claim.", hint: "" }, "success");
    await fetchGlobal();
    await updateSeasonUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

async function claimSeasonReward(seasonId, tokenId) {
  try {
    showTxStatus({ title: "Claim season", message: "Confirm claimSeason in wallet…", hint: "" }, "pending");
    const tx = await vault.claimSeason(seasonId, tokenId);
    await tx.wait();
    showTxStatus({ title: "Season claimed", message: "SATO reward received.", hint: "" }, "success");
    await updateSeasonUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

async function recoverPrizeDraw() {
  try {
    showTxStatus({ title: "Recover draw", message: "Confirm timeout recovery in wallet…", hint: "" }, "pending");
    const tx = await vault.recoverTimedOutPrizeDraw();
    await tx.wait();
    showTxStatus({ title: "Prize recovered", message: "Pending prize returned to prize fund.", hint: "" }, "success");
    await fetchGlobal();
    await updateSeasonUI();
    await updateLotteryUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

async function updateLotteryUI() {
  const el = document.getElementById("lotteryHistory");
  if (!el) return;
  if (!vault) {
    el.innerHTML = '<p class="placeholder-msg">Connect wallet to request draws and claim prizes.</p>';
    return;
  }
  const [prizeFund, canRequest, pendingPrize, pendingRequestId, userPrize] = await Promise.all([
    vault.prizeFund(),
    vault.canRequestPrizeDraw(),
    vault.pendingDrawPrize(),
    vault.pendingDrawRequestId(),
    vault.pendingPrize(userAddress),
  ]);

  let html = '<p class="placeholder-msg">Prize fund: <strong>' + formatSato(prizeFund) + ' SATO</strong></p>';
  if (pendingPrize > 0n && pendingRequestId > 0n) {
    html += '<p class="placeholder-msg">Draw #' + pendingRequestId.toString() + ' pending VRF for ' + formatSato(pendingPrize) + ' SATO.</p>';
  } else if (canRequest) {
    html += '<button class="btn-outline-pill" onclick="requestPrizeDraw()">Request prize draw</button>';
  } else {
    html += '<p class="placeholder-msg">Draw is not available yet. Pool must reach minimum and interval must pass.</p>';
  }
  if (userPrize > 0n) {
    html += '<button class="btn-primary-pill" onclick="claimPrize()">Claim prize: ' + formatSato(userPrize) + ' SATO</button>';
  }
  el.innerHTML = html;
}

async function requestPrizeDraw() {
  try {
    showTxStatus({ title: "Request draw", message: "Confirm Chainlink VRF prize draw request…", hint: "" }, "pending");
    const tx = await vault.requestPrizeDraw();
    await tx.wait();
    showTxStatus({ title: "Draw requested", message: "Waiting for VRF fulfillment.", hint: "" }, "success");
    await fetchGlobal();
    await updateSeasonUI();
    await updateLotteryUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

async function claimPrize() {
  try {
    showTxStatus({ title: "Claim prize", message: "Confirm prize claim in wallet…", hint: "" }, "pending");
    const tx = await vault.claimPrize();
    await tx.wait();
    showTxStatus({ title: "Prize claimed", message: "SATO prize received.", hint: "" }, "success");
    await updateLotteryUI();
  } catch (e) {
    showTxStatus(parseVaultError(e), "error");
  }
}

function parseVaultError(err) {
  const data = findErrorData(err);
  if (data) {
    try {
      const parsed = getVaultIface().parseError(data);
      if (parsed?.name) return humanVaultError(parsed.name);
    } catch {}
  }
  const msg = err?.shortMessage || err?.message || String(err);
  if (msg.includes("user rejected")) return { title: "Cancelled", message: "Rejected in wallet.", hint: "" };
  return { title: "Failed", message: msg.slice(0, 120), hint: "" };
}

function getVaultIface() {
  if (!vaultIface) vaultIface = new ethers.Interface(VAULT_ABI);
  return vaultIface;
}

function findErrorData(value, seen = new Set()) {
  if (!value || typeof value !== "object" || seen.has(value)) return null;
  seen.add(value);
  if (typeof value.data === "string" && value.data.startsWith("0x")) return value.data;
  if (typeof value.error?.data === "string" && value.error.data.startsWith("0x")) return value.error.data;
  for (const key of ["info", "error", "revert", "body"]) {
    const found = findErrorData(value[key], seen);
    if (found) return found;
  }
  return null;
}

function humanVaultError(name) {
  const messages = {
    ExceedsWalletMintLimit: "This wallet already minted the maximum number of stones.",
    DepositTooLow: "Deposit is below the 100 SATO minimum.",
    DepositTooHigh: "Deposit exceeds the current mint cap.",
    NotTokenOwner: "Connected wallet does not own this stone.",
    LockEndedUseRedeem: "Lock already ended. Use redeem instead.",
    LockNotEnded: "Lock is still active.",
    VaultEmpty: "This vault is already empty.",
    SeasonNotEnded: "Season has not ended yet.",
    SeasonAlreadyFinalized: "Season is already finalized.",
    SeasonNotFinalized: "Season is not finalized yet.",
    NothingToClaim: "There is nothing to claim.",
    AlreadyClaimed: "This reward was already claimed.",
    NotSnapshotOwner: "Only the season snapshot owner can claim this reward.",
    SeasonTransferLocked: "Transfers are locked around the season boundary.",
    PrizePoolTooLow: "Prize pool has not reached the draw minimum.",
    PrizeDrawTooSoon: "Prize draw interval has not passed yet.",
    NoPendingPrize: "There is no pending prize to claim or recover.",
    DrawPending: "A prize draw is already pending.",
    NoEligibleTickets: "No active locked stones are eligible for this draw.",
    PrizeDrawNotTimedOut: "VRF draw has not timed out yet.",
  };
  return { title: name, message: messages[name] || ("Contract reverted with " + name + "."), hint: "" };
}

function showTxStatus(payload, type) {
  const el = document.getElementById("txStatus");
  if (!el) return;
  const p = typeof payload === "string" ? { title: "Status", message: payload, hint: "" } : payload;
  el.classList.remove("hidden", "pending", "success", "error");
  el.classList.add(type);
  restartAnimation(el, "tx-flash");
  document.getElementById("txStatusTitle").textContent = p.title || type;
  document.getElementById("txStatusMessage").textContent = p.message || "";
  const h = document.getElementById("txStatusHint");
  if (p.hint) {
    h.textContent = p.hint;
    h.classList.remove("hidden");
  } else h.classList.add("hidden");
}

function formatSato(wei) {
  const raw = ethers.formatUnits(wei, satoDecimals);
  const [whole, frac = ""] = raw.split(".");
  const grouped = BigInt(whole || "0").toLocaleString();
  const decimals = frac.replace(/0+$/, "").slice(0, 2);
  return decimals ? grouped + "." + decimals : grouped;
}

function short(a) {
  return a.slice(0, 6) + "…" + a.slice(-4);
}

function setText(id, t) {
  const el = document.getElementById(id);
  if (el) el.textContent = t;
}

function animateCountText(id, from, to, formatter) {
  const el = document.getElementById(id);
  if (!el) return;
  if (from === to || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    el.textContent = formatter(to);
    return;
  }
  const start = performance.now();
  const duration = 720;
  const delta = to - from;
  function tick(now) {
    const progress = Math.min(1, (now - start) / duration);
    const eased = 1 - Math.pow(1 - progress, 3);
    el.textContent = formatter(Math.round(from + delta * eased));
    if (progress < 1) requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}

function pulseText(id) {
  const el = document.getElementById(id);
  if (el) restartAnimation(el, "motion-pop");
}

function restartAnimation(el, className) {
  el.classList.remove(className);
  void el.offsetWidth;
  el.classList.add(className);
}

function updateMintMotion(lock) {
  const box = document.getElementById("mintBox");
  if (!box) return;
  box.dataset.lock = ["15", "30", "60"][lock] || "15";
  restartAnimation(box, "mint-shift");
}

function updateExplorerLinks() {
  const base = (CONFIG.explorerBaseUrl || "").replace(/\/$/, "");
  const c = document.getElementById("contractLink");
  const t = document.getElementById("tokenLink");
  if (c && CONFIG.contractAddress) c.href = base + "/address/" + CONFIG.contractAddress;
  if (t && CONFIG.satoTokenAddress) t.href = base + "/address/" + CONFIG.satoTokenAddress;
}

function initIntroAnimation() {
  const intro = document.getElementById("intro");
  if (!intro) return;
  setTimeout(() => intro.classList.add("intro-done"), 2200);
}

function initScrollNav() {
  const nav = document.getElementById("nav");
  window.addEventListener("scroll", () => nav?.classList.toggle("nav-scrolled", window.scrollY > 40));
}

function initScrollReveal() {
  document.body.classList.add("motion-ready");
  const targets = document.querySelectorAll(".fade-section, .stagger-item, .appear-up, .whitepaper-teaser-cards > div");
  if (!("IntersectionObserver" in window)) {
    targets.forEach((el) => el.classList.add("in-view"));
    return;
  }
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("in-view");
        observer.unobserve(entry.target);
      }
    });
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
  targets.forEach((el) => observer.observe(el));
}

function initMobileNav() {
  const nav = document.getElementById("nav");
  const btn = document.getElementById("navMenuBtn");
  const links = document.getElementById("navLinks");
  if (!nav || !btn || !links) return;
  btn.addEventListener("click", () => {
    const open = nav.classList.toggle("nav-open");
    btn.setAttribute("aria-expanded", String(open));
  });
  links.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => {
      nav.classList.remove("nav-open");
      btn.setAttribute("aria-expanded", "false");
    });
  });
}

window.connectWallet = connectWallet;
window.approveSato = approveSato;
window.mintStones = mintVault;
window.redeemStone = redeemStone;
window.earlyExitStone = earlyExitStone;
window.finalizePreviousSeason = finalizePreviousSeason;
window.claimSeasonReward = claimSeasonReward;
window.recoverPrizeDraw = recoverPrizeDraw;
window.finalizeSeasonById = finalizeSeasonById;
window.requestPrizeDraw = requestPrizeDraw;
window.claimPrize = claimPrize;
window.updateMintUI = updateMintUI;
