// Lazy-load ethers v6 from CDN with fallback. Returns the global `ethers`.
// Only invoked on user intent (Connect Wallet, first read) to save mobile bandwidth.

const PRIMARY = "https://cdn.jsdelivr.net/npm/ethers@6.7.0/dist/ethers.umd.min.js";
const FALLBACK = "https://unpkg.com/ethers@6.7.0/dist/ethers.umd.min.js";

let loadingPromise = null;

function injectScript(src) {
  return new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = src;
    s.crossOrigin = "anonymous";
    s.referrerPolicy = "no-referrer";
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error("ethers cdn failed: " + src));
    document.head.appendChild(s);
  });
}

export async function loadEthers() {
  if (globalThis.ethers) return globalThis.ethers;
  if (loadingPromise) return loadingPromise;
  loadingPromise = (async () => {
    try {
      await injectScript(PRIMARY);
    } catch {
      await injectScript(FALLBACK);
    }
    if (!globalThis.ethers) throw new Error("ethers failed to attach to window");
    return globalThis.ethers;
  })();
  return loadingPromise;
}

export function ethersIfReady() {
  return globalThis.ethers || null;
}
