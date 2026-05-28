// Shared tx-status panel. Stateless: callers supply a payload object.

import { $, setText } from "./format.js";
import { restartAnimation } from "./animate.js";

export function showTxStatus(payload, type) {
  const el = $("txStatus");
  if (!el) return;
  const p = typeof payload === "string" ? { title: "Status", message: payload, hint: "" } : payload;
  el.classList.remove("hidden", "pending", "success", "error");
  if (type) el.classList.add(type);
  restartAnimation(el, "tx-flash");
  setText("txStatusTitle", p.title || type || "");
  setText("txStatusMessage", p.message || "");
  const h = $("txStatusHint");
  if (!h) return;
  if (p.hint) {
    h.textContent = p.hint;
    h.classList.remove("hidden");
  } else {
    h.classList.add("hidden");
  }
}
