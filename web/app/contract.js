// Vault + SATO ABIs and lightweight contract factories.

export const VAULT_ABI = [
  "function totalMintedEver() view returns (uint256)",
  "function currentSeasonId() view returns (uint256)",
  "function t0() view returns (uint256)",
  "function SEASON_DURATION() view returns (uint256)",
  "function MAX_MINTS_PER_WALLET() view returns (uint256)",
  "function seasonPool(uint256) view returns (uint256)",
  "function seasonFinalized(uint256) view returns (bool)",
  "function snapshotOwner(uint256,uint256) view returns (address)",
  "function seasonClaimed(uint256,uint256) view returns (bool)",
  "function seasonSnapshotStarted() view returns (bool)",
  "function seasonProcessedUntil() view returns (uint256)",
  "function seasonTotalWeight(uint256) view returns (uint256)",
  "function seasonDistributable() view returns (uint256)",
  "function claimableSeasonAmount(uint256,uint256) view returns (uint256)",
  "function prizeFund() view returns (uint256)",
  "function pendingDrawPrize() view returns (uint256)",
  "function pendingDrawRequestId() view returns (uint256)",
  "function pendingPrize(address) view returns (uint256)",
  "function prizeSnapshotStarted() view returns (bool)",
  "function prizeSnapshotNextTokenId() view returns (uint256)",
  "function pendingDrawTotalWeight() view returns (uint256)",
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
  "function processSeasonSnapshot(uint256 seasonId, uint256 maxTokens) external returns (bool)",
  "function claimSeason(uint256 seasonId, uint256 tokenId) external",
  "function requestPrizeDraw() external returns (uint256)",
  "function processPrizeDrawSnapshot(uint256 maxTokens) external returns (bool done, uint256 requestId)",
  "function recoverTimedOutPrizeDraw() external",
  "function claimPrize() external",
  "function previewMint(uint256 grossAmount, uint8 lockDays) view returns (uint256 peakSato, uint32 weight, uint8 rarity)",
  "function vaults(uint256) view returns (uint256 peakSato, uint256 satoLocked, uint64 lockEnd, uint32 weightAtMint, uint8 lockDays, uint8 rarity, bool redeemed)",
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
  "error InvalidSeason()",
  "error SeasonEnded()",
  "error PrizePoolTooLow()",
  "error PrizeDrawTooSoon()",
  "error NoPendingPrize()",
  "error OnlyVRFCoordinator()",
  "error InvalidDrawRequest()",
  "error DrawPending()",
  "error NoEligibleTickets()",
  "error PrizeDrawNotTimedOut()",
  "event StoneMinted(address indexed minter, uint256 indexed tokenId, uint256 grossSato, uint256 peakSato, uint8 lockDays, uint32 weightAtMint)",
];

export const SATO_ABI = [
  "function approve(address,uint256) returns (bool)",
  "function allowance(address,address) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

// Multicall3 (canonical address on every EVM chain in CONFIG).
export const MULTICALL3_ABI = [
  "function aggregate3((address target, bool allowFailure, bytes callData)[] calls) view returns ((bool success, bytes returnData)[] returnData)",
];

let vaultIface;

export function getVaultIface(ethers) {
  if (!vaultIface) vaultIface = new ethers.Interface(VAULT_ABI);
  return vaultIface;
}

export function makeReadProvider(ethers, rpc) {
  return new ethers.JsonRpcProvider(rpc);
}
