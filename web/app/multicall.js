// Thin Multicall3 helper. Pre-encodes calls, decodes results.

import { CONFIG } from "./state.js";
import { MULTICALL3_ABI, VAULT_ABI } from "./contract.js";

let mcIface;
let vIface;

function getMcIface(ethers) {
  if (!mcIface) mcIface = new ethers.Interface(MULTICALL3_ABI);
  return mcIface;
}

function getVIface(ethers) {
  if (!vIface) vIface = new ethers.Interface(VAULT_ABI);
  return vIface;
}

/**
 * Call multiple vault view functions in a single RPC roundtrip.
 * @param {object} provider - ethers Provider
 * @param {Array<{method:string, args?:any[], allowFailure?:boolean}>} calls
 * @returns {Promise<any[]>} decoded results aligned with `calls`
 */
export async function multicallVault(provider, calls) {
  const ethers = globalThis.ethers;
  if (!ethers) throw new Error("ethers not loaded");
  const vIfaceLocal = getVIface(ethers);
  const mcIfaceLocal = getMcIface(ethers);
  const target = CONFIG.contractAddress;
  const aggregateInput = calls.map((c) => ({
    target,
    allowFailure: c.allowFailure ?? false,
    callData: vIfaceLocal.encodeFunctionData(c.method, c.args || []),
  }));
  const data = mcIfaceLocal.encodeFunctionData("aggregate3", [aggregateInput]);
  const ret = await provider.call({ to: CONFIG.multicall3, data });
  const [decoded] = mcIfaceLocal.decodeFunctionResult("aggregate3", ret);
  return decoded.map((r, i) => {
    if (!r.success) return null;
    const result = vIfaceLocal.decodeFunctionResult(calls[i].method, r.returnData);
    return result.length === 1 ? result[0] : result;
  });
}
