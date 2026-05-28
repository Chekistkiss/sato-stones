// Copy to web/config.js after deploy
window.SATO_STONES_CONFIG = {
  contractAddress: "0xYourVaultAddress",
  satoTokenAddress: "0xYourSatoTokenAddress",
  vrfAddress: "0xYourVrfOptional",
  chainId: 11155111,
  chainName: "Sepolia",
  rpcUrls: ["https://ethereum-sepolia-rpc.publicnode.com"],
  explorerBaseUrl: "https://sepolia.etherscan.io",
  maxSupply: 2100,
  // Optional. Leave empty to use the on-chain multicall path.
  // Once your Ponder indexer is deployed, set this to e.g. "https://indexer.satostones.xyz".
  indexerUrl: "",
};
