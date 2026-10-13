// Whimsy levels, docs/v0.2-spec.md section 7. CSS does the moving; this decides what plays.
import { prefs, setPref, type Appearance, type Whimsy } from "./prefs";

const reduce = typeof matchMedia !== "undefined" ? matchMedia("(prefers-reduced-motion: reduce)") : null;

export function level(): Whimsy {
  return reduce?.matches ? "off" : prefs.whimsy;
}
export const full = () => level() === "full";
export const moving = () => level() !== "off";

export function applyWhimsy(w?: Whimsy): void {
  if (w) setPref("whimsy", w);
  document.documentElement.dataset.whimsy = level();
}
reduce?.addEventListener?.("change", () => applyWhimsy());

/** Restart a CSS animation class on an element. */
export function replay(el: Element, cls: string): void {
  el.classList.remove(cls);
  void (el as HTMLElement).offsetWidth;
  el.classList.add(cls);
}

/** Runs `fn` after an animation, or at once when motion is off. Never relies on animationend alone. */
export function after(ms: number, fn: () => void): void {
  if (!moving()) { fn(); return; }
  setTimeout(fn, ms);
}

export function applyAppearance(a: Appearance, animate = false): void {
  setPref("appearance", a);
  const root = document.documentElement;
  if (animate && moving()) {
    root.classList.add("theming");
    setTimeout(() => root.classList.remove("theming"), 420);
  }
  if (a === "system") root.removeAttribute("data-theme");
  else root.setAttribute("data-theme", a);
}

/** Six ink flecks from the centre of `host`. */
export function burst(host: HTMLElement): void {
  if (!full()) return;
  const inks = ["var(--accent)", "var(--overdue)", "var(--rule)", "var(--accent)", "var(--teal)", "var(--overdue)"];
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2 + 0.4, r = 18 + (i % 2) * 6;
    const dot = document.createElement("span");
    dot.className = "fleck";
    dot.setAttribute("aria-hidden", "true");
    dot.style.background = inks[i];
    dot.style.setProperty("--dx", `${Math.round(Math.cos(a) * r)}px`);
    dot.style.setProperty("--dy", `${Math.round(Math.sin(a) * r)}px`);
    host.append(dot);
    setTimeout(() => dot.remove(), 700);
  }
}
