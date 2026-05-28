// Optional indexer client. Lives alongside the on-chain multicall fallback.
//
// Reads `window.SATO_STONES_CONFIG.indexerUrl`. If unset or unreachable within
// the timeout, callers should fall back to the on-chain multicall path.

import { CONFIG } from "./state.js";

const DEFAULT_TIMEOUT_MS = 1500;

export function indexerEnabled() {
  return typeof CONFIG.indexerUrl === "string" && CONFIG.indexerUrl.length > 0;
}

async function fetchJson(path, { timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  if (!indexerEnabled()) throw new Error("indexer not configured");
  const url = `${CONFIG.indexerUrl.replace(/\/$/, "")}${path}`;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      headers: { accept: "application/json" },
    });
    if (!res.ok) throw new Error(`indexer ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

export async function fetchGlobalStats() {
  return fetchJson("/stats");
}

export async function fetchOwnerStones(address) {
  if (!address) return null;
  return fetchJson(`/owners/${address.toLowerCase()}`);
}

export async function fetchStone(tokenId) {
  return fetchJson(`/stones/${tokenId}`);
}

export async function fetchRecentEvents({ kind, actor, limit = 25 } = {}) {
  const params = new URLSearchParams();
  if (kind) params.set("kind", kind);
  if (actor) params.set("actor", actor.toLowerCase());
  params.set("limit", String(limit));
  return fetchJson(`/events?${params.toString()}`);
}

export async function fetchDraws() {
  return fetchJson("/draws");
}

export async function fetchLeaderboard(limit = 25) {
  return fetchJson(`/leaderboard?limit=${limit}`);
}

// Wrap any indexer call. On error, returns null and lets caller fall back.
export async function tryIndexer(fn, ...args) {
  if (!indexerEnabled()) return null;
  try {
    return await fn(...args);
  } catch (err) {
    if (typeof console !== "undefined") {
      console.warn("[indexer] falling back:", err?.message ?? err);
    }
    return null;
  }
}
