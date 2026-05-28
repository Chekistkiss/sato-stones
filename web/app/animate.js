// Tactile micro-animations — no framework, no deps.
// All functions respect prefers-reduced-motion.

const REDUCED = () => globalThis.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

// --- IntersectionObserver scroll reveal ---
export function initScrollReveal() {
  document.body.classList.add("motion-ready");
  const targets = document.querySelectorAll(
    ".fade-section, .stagger-item, .appear-up, .whitepaper-teaser-cards > div"
  );
  if (!("IntersectionObserver" in window)) {
    targets.forEach((el) => el.classList.add("in-view"));
    return;
  }
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in-view");
          observer.unobserve(entry.target);
        }
      });
    },
    { rootMargin: "0px 0px -8% 0px", threshold: 0.12 }
  );
  targets.forEach((el) => observer.observe(el));
}

// --- Rolling-digit odometer for counters ---
// Renders the target number as a stack of digit cells and animates Y-translation.
// Falls back to text replacement under reduced-motion.
const digitState = new WeakMap();

export function animateDigits(el, value, formatter = (v) => String(v)) {
  if (!el) return;
  const text = formatter(value);
  if (REDUCED()) {
    el.textContent = text;
    return;
  }
  const prev = digitState.get(el) || "";
  if (prev === text) return;
  digitState.set(el, text);

  // Rebuild only if structural length differs or no children yet.
  if (el.dataset.odometer !== "1" || prev.length !== text.length) {
    el.dataset.odometer = "1";
    el.innerHTML = "";
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (/\d/.test(ch)) {
        const cell = document.createElement("span");
        cell.className = "digit";
        const stack = document.createElement("span");
        stack.className = "digit-stack";
        for (let n = 0; n <= 9; n++) {
          const slot = document.createElement("span");
          slot.textContent = String(n);
          stack.appendChild(slot);
        }
        cell.appendChild(stack);
        cell.dataset.digit = ch;
        el.appendChild(cell);
      } else {
        const sep = document.createElement("span");
        sep.textContent = ch;
        sep.className = "digit-static";
        el.appendChild(sep);
      }
    }
  }

  // Update each digit's translate.
  const cells = el.querySelectorAll(".digit");
  let cellIdx = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (/\d/.test(ch)) {
      const cell = cells[cellIdx++];
      if (!cell) continue;
      const stack = cell.querySelector(".digit-stack");
      const n = Number(ch);
      stack.style.transform = `translateY(-${n}em)`;
      cell.dataset.digit = ch;
    }
  }
}

// --- Easy animated count for plain text (used where digit odometer is overkill) ---
export function animateCountText(el, from, to, formatter = (v) => String(v)) {
  if (!el) return;
  if (from === to || REDUCED()) {
    el.textContent = formatter(to);
    return;
  }
  const start = performance.now();
  const duration = 720;
  const delta = to - from;
  function tick(now) {
    const progress = Math.min(1, (now - start) / duration);
    const eased = 1 - Math.pow(1 - progress, 3);
    el.textContent = formatter(Math.round(from + delta * eased));
    if (progress < 1) requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}

export function restartAnimation(el, className) {
  if (!el) return;
  el.classList.remove(className);
  // force reflow
  // eslint-disable-next-line no-unused-expressions
  el.offsetWidth;
  el.classList.add(className);
}

export function pulse(el) {
  restartAnimation(el, "motion-pop");
}

// --- Tier card 3D tilt micro-parallax (pointer + tilt-on class) ---
export function initTierCardTilt() {
  if (REDUCED()) return;
  const cards = document.querySelectorAll(".tier-card");
  cards.forEach((card) => {
    card.classList.add("tilt-on");
    card.addEventListener("pointermove", (e) => {
      const rect = card.getBoundingClientRect();
      const px = (e.clientX - rect.left) / rect.width - 0.5;
      const py = (e.clientY - rect.top) / rect.height - 0.5;
      card.style.setProperty("--tilt-y", `${px * 1.6}deg`);
      card.style.setProperty("--tilt-x", `${-py * 1.4}deg`);
    });
    card.addEventListener("pointerleave", () => {
      card.style.setProperty("--tilt-x", "0deg");
      card.style.setProperty("--tilt-y", "0deg");
    });
  });
}
