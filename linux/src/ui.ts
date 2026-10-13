// DOM helpers, icons, toasts and popovers.
import { moving } from "./motion";

export function el<K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Record<string, any> = {}, ...children: (Node | string | null | undefined | false)[]): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === "class") e.className = v;
    else if (k === "html") e.innerHTML = v;
    else if (k === "style") e.setAttribute("style", v);
    else if (k === "value") (e as HTMLInputElement).value = String(v);
    else if (k === "checked") (e as HTMLInputElement).checked = !!v;
    else if (k === "dataset") Object.assign(e.dataset, v);
    else if (k.startsWith("on") && typeof v === "function") e.addEventListener(k.slice(2).toLowerCase(), v);
    else e.setAttribute(k, v === true ? "" : String(v));
  }
  for (const c of children) if (c != null && c !== false) e.append(c);
  return e;
}

export const $ = <T extends HTMLElement = HTMLElement>(sel: string, root: ParentNode = document) => root.querySelector(sel) as T | null;

const svg = (paths: string, size = 20, extra = "") =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${paths}</svg>`;

export const I = {
  sidebar: svg('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M9 5v14"/>'),
  search: svg('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', 16),
  plus: svg('<path d="M12 5v14M5 12h14"/>', 16, 'stroke-width="2.2"'),
  chevron: svg('<path d="m6 9 6 6 6-6"/>', 14, 'stroke-width="2.2"'),
  left: svg('<path d="m15 6-6 6 6 6"/>', 16, 'stroke-width="2"'),
  right: svg('<path d="m9 6 6 6-6 6"/>', 16, 'stroke-width="2"'),
  check: svg('<path class="tick" d="m5 12 5 5L20 7" stroke-dasharray="24"/>', 13, 'stroke="var(--accent-ink)" stroke-width="3"'),
  checkMuted: svg('<path d="m5 12 5 5L20 7"/>', 14, 'stroke-width="2.6"'),
  slash: svg('<path d="m17 7-10 10"/>', 20, 'stroke="var(--rule)" stroke-width="1.6"'),
  export: svg('<path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 19h14"/>'),
  insert: svg('<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M12 8v8M8 12h8"/>'),
  gear: svg('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  sun: svg('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'),
  moon: svg('<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>'),
  auto: svg('<circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor"/>'),
  calendar: svg('<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>', 16),
  x: svg('<path d="M6 6l12 12M18 6 6 18"/>', 12, 'stroke-width="2.4"'),
  move: svg('<path d="M12 3v18M3 12h18M12 3l-3 3M12 3l3 3M12 21l-3-3M12 21l3-3M3 12l3-3M3 12l3 3M21 12l-3-3M21 12l-3 3"/>', 16, 'stroke-width="2"'),
  rotate: svg('<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/>', 16, 'stroke-width="2"'),
  duplicate: svg('<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>', 16),
  trash: svg('<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>', 16, 'stroke-width="1.9"'),
  grip: '<svg width="12" height="16" viewBox="0 0 12 16" fill="currentColor" aria-hidden="true"><circle cx="3" cy="3" r="1.3"/><circle cx="9" cy="3" r="1.3"/><circle cx="3" cy="8" r="1.3"/><circle cx="9" cy="8" r="1.3"/><circle cx="3" cy="13" r="1.3"/><circle cx="9" cy="13" r="1.3"/></svg>',
  markdown: svg('<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 15V9l2.5 3L12 9v6M16 9v6M14 13l2 2 2-2"/>', 16),
  clearDone: svg('<path d="m4 12 4 4 8-8"/><path d="M14 16h6"/>', 16, 'stroke-width="2"'),
  sort: svg('<path d="M4 6h10M4 12h7M4 18h4M17 5v14M14 16l3 3 3-3"/>', 16),
  text: svg('<path d="M4 6h16M4 12h10M4 18h14"/>', 16),
  table: svg('<rect x="3" y="4" width="18" height="16" rx="1"/><path d="M3 10h18M3 15h18M10 4v16"/>', 16),
  image: svg('<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-8 8"/>', 16),
  imageBig: svg('<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-8 8"/>', 28),
  file: svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>', 20),
  link: svg('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>', 16),
  code: svg('<path d="m16 18 6-6-6-6M8 6l-6 6 6 6"/>', 16),
  divider: svg('<path d="M4 12h16"/>', 16),
  open: svg('<path d="M14 5h5v5M19 5l-8 8M19 13v5a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/>', 14),
  pin: svg('<path d="M12 17v5M5 17h14l-2-4V5H7v8z"/>', 16),
  newSheet: svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M12 11v6M9 14h6"/>', 16),
};

// ---------- toasts ----------

let toastTimer: number | undefined;
export function toast(msg: string, action?: { label: string; run: () => void }, ms = 3000): void {
  document.querySelector(".toast")?.remove();
  const t = el("div", { class: "toast", role: "status" }, el("span", {}, msg));
  if (action) t.append(el("button", { class: "toast-action", onClick: () => { t.remove(); action.run(); } }, action.label));
  document.body.append(t);
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => {
    t.classList.add("leaving");
    setTimeout(() => t.remove(), moving() ? 200 : 0);
  }, action ? 8000 : ms);
}

// ---------- popovers and menus ----------

let openPop: { el: HTMLElement; close: () => void } | null = null;

export function closePopover(): void { openPop?.close(); }

/** Opens `content` anchored under `anchor` (or at a point). Closes on outside click, Escape, or a second open. */
export function popover(content: HTMLElement, at: HTMLElement | { x: number; y: number }, opts: { align?: "start" | "end"; className?: string; onClose?: () => void } = {}): () => void {
  closePopover();
  const pop = el("div", { class: `popover ${opts.className ?? ""}` }, content);
  document.body.append(pop);
  const r = at instanceof HTMLElement ? at.getBoundingClientRect() : { left: at.x, right: at.x, bottom: at.y, top: at.y };
  const w = pop.offsetWidth, h = pop.offsetHeight;
  let left = opts.align === "end" ? r.right - w : r.left;
  left = Math.max(8, Math.min(left, window.innerWidth - w - 8));
  let top = r.bottom + 6;
  if (top + h > window.innerHeight - 8) top = Math.max(8, r.top - h - 6);
  pop.style.left = `${left}px`;
  pop.style.top = `${top}px`;
  pop.style.transformOrigin = `${opts.align === "end" ? "top right" : "top left"}`;
  const onDown = (e: Event) => {
    const t = e.target as Node;
    if (pop.contains(t) || (at instanceof HTMLElement && at.contains(t))) return;
    close();
  };
  const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); close(); } };
  const close = () => {
    if (!pop.isConnected) return;
    document.removeEventListener("pointerdown", onDown, true);
    document.removeEventListener("keydown", onKey, true);
    pop.remove();
    if (openPop?.el === pop) openPop = null;
    opts.onClose?.();
  };
  setTimeout(() => document.addEventListener("pointerdown", onDown, true), 0);
  document.addEventListener("keydown", onKey, true);
  openPop = { el: pop, close };
  (pop.querySelector("input, button, [tabindex]") as HTMLElement | null)?.focus();
  return close;
}

export interface MenuItem { label: string; icon?: string; key?: string; checked?: boolean; danger?: boolean; run: () => void }

export function menu(items: (MenuItem | "sep")[], at: HTMLElement | { x: number; y: number }, align: "start" | "end" = "start"): void {
  const list = el("div", { class: "menu", role: "menu" });
  let close = () => {};
  for (const it of items) {
    if (it === "sep") { list.append(el("div", { class: "sep", role: "separator" })); continue; }
    list.append(el("button", { role: it.checked === undefined ? "menuitem" : "menuitemradio", "aria-checked": it.checked === undefined ? null : String(it.checked),
      class: `${it.danger ? "danger" : ""}`, onClick: () => { close(); it.run(); } },
      it.checked !== undefined ? el("span", { class: "mark", html: it.checked ? I.checkMuted : "" }) : it.icon ? el("span", { class: "ico", html: it.icon }) : null,
      el("span", { class: "label" }, it.label), it.key ? el("span", { class: "key" }, it.key) : null));
  }
  list.addEventListener("keydown", (e) => {
    const btns = [...list.querySelectorAll("button")] as HTMLButtonElement[];
    const i = btns.indexOf(document.activeElement as HTMLButtonElement);
    if (e.key === "ArrowDown") { e.preventDefault(); btns[(i + 1) % btns.length].focus(); }
    if (e.key === "ArrowUp") { e.preventDefault(); btns[(i - 1 + btns.length) % btns.length].focus(); }
  });
  close = popover(list, at, { align });
}

export function segmented<T extends string>(label: string, options: { value: T; label: string }[], value: T, onPick: (v: T) => void): HTMLElement {
  const g = el("div", { class: "seg", role: "group", "aria-label": label });
  for (const o of options) {
    g.append(el("button", { "aria-pressed": String(o.value === value), class: o.value === value ? "on" : "", onClick: () => {
      g.querySelectorAll("button").forEach((b) => { b.classList.remove("on"); b.setAttribute("aria-pressed", "false"); });
      const b = [...g.querySelectorAll("button")].find((x) => x.textContent === o.label)!;
      b.classList.add("on"); b.setAttribute("aria-pressed", "true");
      onPick(o.value);
    } }, o.label));
  }
  return g;
}

export function editing(): boolean {
  const a = document.activeElement;
  return a instanceof HTMLInputElement || a instanceof HTMLTextAreaElement || a instanceof HTMLSelectElement;
}
