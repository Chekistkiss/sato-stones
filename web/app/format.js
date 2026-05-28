// Formatters and small DOM helpers.

import { state } from "./state.js";

export function formatSato(wei) {
  const ethers = globalThis.ethers;
  if (!ethers) return String(wei);
  const raw = ethers.formatUnits(wei, state.satoDecimals);
  const [whole, frac = ""] = raw.split(".");
  const grouped = BigInt(whole || "0").toLocaleString();
  const decimals = frac.replace(/0+$/, "").slice(0, 2);
  return decimals ? grouped + "." + decimals : grouped;
}

export function short(a) {
  if (!a) return "";
  return a.slice(0, 6) + "…" + a.slice(-4);
}

export function setText(id, t) {
  const el = document.getElementById(id);
  if (el) el.textContent = t;
}

export function $(id) {
  return document.getElementById(id);
}

// Human-readable countdown for unix seconds offsets.
export function formatCountdown(seconds) {
  if (!Number.isFinite(seconds) || seconds <= 0) return "any moment";
  const s = Math.floor(seconds);
  const days = Math.floor(s / 86400);
  const hours = Math.floor((s % 86400) / 3600);
  const mins = Math.floor((s % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${mins}m`;
  if (mins > 0) return `${mins}m`;
  return `${s}s`;
}
