// Vault revert decoding + degen-tone messages.
// Many errors carry context (lockEnd, drawCooldown). The decoder consumes
// optional context from the caller and produces friendlier copy.

import { getVaultIface } from "./contract.js";
import { formatCountdown } from "./format.js";

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

function human(name, ctx = {}) {
  const messages = {
    MintedOut: () => ({ title: "Sold out", message: "All 2,100 Sato Stones have been minted." }),
    ExceedsWalletMintLimit: () => ({ title: "Wallet cap", message: "This wallet already minted the maximum number of Stones." }),
    DepositTooLow: () => ({ title: "Below minimum", message: "Deposit is below the 100 SATO minimum." }),
    DepositTooHigh: () => ({ title: "Above cap", message: "Deposit exceeds the current mint cap." }),
    NotTokenOwner: () => ({ title: "Not your Stone", message: "Connected wallet does not own this Stone." }),
    LockEndedUseRedeem: () => ({ title: "Lock ended", message: "Use Redeem instead — your SATO is already unlockable." }),
    LockNotEnded: () => {
      const remaining = ctx.lockSecondsRemaining;
      const hint = Number.isFinite(remaining)
        ? `Unlocks in ${formatCountdown(remaining)}.`
        : "Wait for the lock to end.";
      return { title: "Still locked", message: hint };
    },
    VaultEmpty: () => ({ title: "Already empty", message: "This Stone has no locked SATO left." }),
    SeasonNotEnded: () => {
      const remaining = ctx.seasonSecondsRemaining;
      const hint = Number.isFinite(remaining)
        ? `Reward season ends in ${formatCountdown(remaining)}.`
        : "Season has not ended yet.";
      return { title: "Season still open", message: hint };
    },
    SeasonAlreadyFinalized: () => ({ title: "Already finalized", message: "Season has already been finalized." }),
    SeasonNotFinalized: () => ({ title: "Not finalized", message: "Finalize the reward season first." }),
    NothingToClaim: () => ({ title: "Nothing to claim", message: "No rewards available for this Stone." }),
    AlreadyClaimed: () => ({ title: "Already claimed", message: "This reward was already claimed." }),
    NotSnapshotOwner: () => ({ title: "Not the holder", message: "Only the wallet that held this Stone at finalization can claim." }),
    SeasonTransferLocked: () => ({ title: "Transfer locked", message: "Transfers are paused near the season boundary." }),
    InvalidSeason: () => ({ title: "Invalid season", message: "Only season 0 exists in this build." }),
    SeasonEnded: () => ({ title: "Mint window closed", message: "Minting closes when the reward season ends." }),
    PrizePoolTooLow: () => ({ title: "Pool too low", message: "Prize pool has not reached the draw minimum yet." }),
    PrizeDrawTooSoon: () => {
      const remaining = ctx.drawCooldownRemaining;
      const hint = Number.isFinite(remaining)
        ? `Next draw eligible in ${formatCountdown(remaining)}.`
        : "Draw interval has not passed.";
      return { title: "Draw cooldown", message: hint };
    },
    NoPendingPrize: () => ({ title: "Nothing pending", message: "No pending prize to claim or recover." }),
    OnlyVRFCoordinator: () => ({ title: "VRF only", message: "Only the Chainlink VRF coordinator can call this." }),
    InvalidDrawRequest: () => ({ title: "Stale draw", message: "This VRF request id no longer matches a pending draw." }),
    DrawPending: () => ({ title: "Draw pending", message: "A prize draw is already pending." }),
    NoEligibleTickets: () => ({ title: "No tickets", message: "No active locked Stones are eligible for this draw." }),
    PrizeDrawNotTimedOut: () => ({ title: "Not timed out", message: "VRF draw has not timed out yet." }),
  };
  const build = messages[name];
  const out = build ? build() : { title: name, message: `Contract reverted with ${name}.` };
  return { ...out, hint: "" };
}

export function parseVaultError(err, ctx = {}) {
  const data = findErrorData(err);
  if (data) {
    try {
      const parsed = getVaultIface(globalThis.ethers).parseError(data);
      if (parsed?.name) return human(parsed.name, ctx);
    } catch {}
  }
  const msg = err?.shortMessage || err?.message || String(err);
  if (msg.includes("user rejected") || msg.toLowerCase().includes("denied")) {
    return { title: "Cancelled", message: "Rejected in wallet.", hint: "" };
  }
  if (msg.includes("insufficient funds")) {
    return { title: "Out of gas money", message: "Not enough ETH in this wallet to cover gas.", hint: "" };
  }
  return { title: "Failed", message: msg.slice(0, 160), hint: "" };
}
