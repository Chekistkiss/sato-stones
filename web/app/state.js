// Global runtime state for the Sato Stones dApp.
// Lives outside any framework — read/write directly.

export const DEFAULT_CONFIG = {
  contractAddress: "0x0000000000000000000000000000000000000000",
  satoTokenAddress: "0x0000000000000000000000000000000000000000",
  chainId: 11155111,
  chainName: "Sepolia",
  rpcUrls: ["https://ethereum-sepolia-rpc.publicnode.com"],
  explorerBaseUrl: "https://sepolia.etherscan.io",
  maxSupply: 2100,
  indexerUrl: "",
  multicall3: "0xcA11bde05977b3631167028862bE2a173976CA11",
};

export const CONFIG = { ...DEFAULT_CONFIG, ...(globalThis.SATO_STONES_CONFIG || {}) };

export const LOCK = Object.freeze({ Fifteen: 0, Thirty: 1, Sixty: 2 });
export const RARITY = Object.freeze(["Common", "Uncommon", "Rare", "Mythic"]);

export const state = {
  provider: null,
  signer: null,
  userAddress: null,
  vault: null,
  sato: null,
  satoDecimals: 18,
  isDemo: true,
  walletListenersInstalled: false,
  mintUiNonce: 0,
  minted: 0,
  previousMinted: 0,
  season: 0,
  pool: 0n,
  prize: 0n,
  userTokenIds: [],
};

export function resetWalletStateValues() {
  state.provider = null;
  state.signer = null;
  state.userAddress = null;
  state.vault = null;
  state.sato = null;
  state.userTokenIds = [];
}
