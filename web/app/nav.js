// Navigation: scroll shadow, mobile drawer, scroll-spy, mobile sticky CTA.

import { state } from "./state.js";

const SECTION_IDS = ["hero", "stats", "vault", "lottery", "mint", "stones", "seasons", "whitepaper"];

export function initNav() {
  initScrollShadow();
  initMobileDrawer();
  initScrollSpy();
  initIntro();
}

function initScrollShadow() {
  const nav = document.getElementById("nav");
  if (!nav) return;
  const set = () => nav.classList.toggle("scrolled", window.scrollY > 40);
  window.addEventListener("scroll", set, { passive: true });
  set();
}

function initMobileDrawer() {
  const nav = document.getElementById("nav");
  const btn = document.getElementById("navMenuBtn");
  const links = document.getElementById("navLinks");
  if (!nav || !btn || !links) return;
  btn.addEventListener("click", () => {
    const open = nav.classList.toggle("nav-open");
    btn.setAttribute("aria-expanded", String(open));
    btn.setAttribute("aria-label", open ? "Close menu" : "Open menu");
  });
  links.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => {
      nav.classList.remove("nav-open");
      btn.setAttribute("aria-expanded", "false");
    });
  });
}

function initScrollSpy() {
  const navLinks = document.querySelectorAll("#navLinks a[href^='#']");
  if (!navLinks.length || !("IntersectionObserver" in window)) return;
  const map = new Map();
  navLinks.forEach((a) => {
    const id = a.getAttribute("href")?.slice(1);
    if (id) map.set(id, a);
  });
  const observer = new IntersectionObserver(
    (entries) => {
      let topMost = null;
      entries.forEach((e) => {
        if (e.isIntersecting && (!topMost || e.boundingClientRect.top < topMost.boundingClientRect.top)) {
          topMost = e;
        }
      });
      if (topMost) {
        const id = topMost.target.id;
        navLinks.forEach((a) => a.classList.toggle("active", a.getAttribute("href") === "#" + id));
      }
    },
    { rootMargin: "-40% 0px -55% 0px", threshold: [0, 0.4] }
  );
  SECTION_IDS.forEach((id) => {
    const el = document.getElementById(id);
    if (el) observer.observe(el);
  });
}

function initIntro() {
  const intro = document.getElementById("intro");
  if (!intro) return;
  setTimeout(() => intro.classList.add("intro-done"), 2200);
}

// Mobile sticky CTA — context-aware label.
export function initMobileCta({ onConnect, onMint, onClaim }) {
  const bar = document.getElementById("mobileCtaBar");
  const btn = document.getElementById("mobileCtaBtn");
  if (!bar || !btn) return;
  bar.removeAttribute("aria-hidden");

  let mode = "connect";
  function set(modeName, label, disabled = false) {
    if (mode === modeName && btn.textContent === label && btn.disabled === disabled) return;
    mode = modeName;
    btn.textContent = label;
    btn.disabled = disabled;
  }
  function refresh() {
    if (!state.signer) {
      set("connect", "Connect Wallet");
      return;
    }
    // If we are in #stones / #seasons sections, default to "Claim/Manage".
    const hash = (window.location.hash || "").replace("#", "");
    const inClaim = hash === "seasons" || hash === "stones";
    if (inClaim) {
      set("claim", "Open claims");
    } else {
      const mintBtn = document.getElementById("mintBtn");
      const disabled = !!mintBtn?.disabled;
      set("mint", "Mint Vault Stone", disabled);
    }
  }
  btn.addEventListener("click", () => {
    if (mode === "connect") return onConnect();
    if (mode === "mint") return onMint();
    if (mode === "claim") {
      const target = document.getElementById("seasons") || document.getElementById("stones");
      target?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  });
  window.addEventListener("hashchange", refresh);
  window.addEventListener("scroll", refresh, { passive: true });
  refresh();
  return { refresh };
}
