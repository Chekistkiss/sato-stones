// Wallet connect / network switch / account lifecycle.

import { CONFIG, state, resetWalletStateValues } from "./state.js";
import { VAULT_ABI, SATO_ABI } from "./contract.js";
import { loadEthers } from "./ethers-loader.js";
import { short, $, setText } from "./format.js";
import { showTxStatus } from "./tx-status.js";
import { parseVaultError } from "./errors.js";

let onConnectedHook = null;
let onResetHook = null;

export function setHooks({ onConnected, onReset }) {
  onConnectedHook = onConnected || null;
  onResetHook = onReset || null;
}

export async function connectWallet() {
  if (!globalThis.ethereum && !window.ethereum) {
    showTxStatus({ title: "No wallet", message: "Install MetaMask or open in a wallet browser.", hint: "" }, "error");
    return;
  }
  const ethers = await loadEthers();
  state.provider = new ethers.BrowserProvider(window.ethereum);
  if (!(await ensureConfiguredNetwork())) return;
  installWalletListeners();
  state.signer = await state.provider.getSigner();
  state.userAddress = await state.signer.getAddress();
  state.vault = new ethers.Contract(CONFIG.contractAddress, VAULT_ABI, state.signer);
  state.sato = new ethers.Contract(CONFIG.satoTokenAddress, SATO_ABI, state.signer);
  try {
    state.satoDecimals = Number(await state.sato.decimals());
  } catch {
    state.satoDecimals = 18;
  }

  $("mintDisconnected")?.classList.add("hidden");
  $("mintConnected")?.classList.remove("hidden");
  setText("mintAddr", short(state.userAddress));
  setText("navConnectBtn", short(state.userAddress));

  if (onConnectedHook) await onConnectedHook();
}

async function ensureConfiguredNetwork() {
  const ethers = globalThis.ethers;
  const net = await state.provider.getNetwork();
  if (Number(net.chainId) === CONFIG.chainId) return true;
  const chainIdHex = "0x" + CONFIG.chainId.toString(16);
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: chainIdHex }] });
    state.provider = new ethers.BrowserProvider(window.ethereum);
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
        state.provider = new ethers.BrowserProvider(window.ethereum);
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
  if (state.walletListenersInstalled || !window.ethereum?.on) return;
  state.walletListenersInstalled = true;
  window.ethereum.on("accountsChanged", () => resetWalletState("Wallet account changed. Reconnect to continue."));
  window.ethereum.on("chainChanged", () => resetWalletState("Network changed. Reconnect on " + CONFIG.chainName + "."));
}

function resetWalletState(message) {
  resetWalletStateValues();
  $("mintDisconnected")?.classList.remove("hidden");
  $("mintConnected")?.classList.add("hidden");
  setText("navConnectBtn", "Connect Wallet");
  setText("stonesDisconnected", "Connect wallet to view your stones.");
  $("stonesDisconnected")?.classList.remove("hidden");
  $("stonesGrid")?.classList.add("hidden");
  if (onResetHook) onResetHook();
  showTxStatus({ title: "Wallet changed", message, hint: "" }, "error");
}
