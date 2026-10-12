import { api, isTauri } from "./api";
import {
  GRID, type Block, type BlockKind, type Pad, type Todo, counts, isOverdue, newTodo, nextFreePoint, nextStatus,
  padded, slugify, snap, snapBlock, uid, dailyPad, TODO_ROWS,
} from "./model";
import { classify, fromDataTransfer, type ClipboardContents, type PasteResult } from "./paste";
import { applyAppearance, loadAppearance, nextAppearance, type Appearance } from "./theme";

// ---------- state ----------

const state = {
  pads: [] as Pad[],
  current: null as Pad | null,
  selected: null as string | null,
  railOpen: window.innerWidth > 960,
  appearance: loadAppearance() as Appearance,
  lastPoint: null as { x: number; y: number } | null,
};

let saveTimer: number | undefined;
function touch(): void {
  window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(flush, 400);
}
async function flush(): Promise<void> {
  if (!state.current) return;
  const pad = state.current;
  await api.savePad(pad).catch((e) => toast(String(e)));
  const i = state.pads.findIndex((p) => p.id === pad.id);
  if (i >= 0) state.pads[i] = pad; else state.pads = await api.listPads();
  renderRail();
}

// ---------- icons (inline stroke SVG, never emoji) ----------

const svg = (paths: string, size = 20, extra = "") =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${paths}</svg>`;
const I = {
  sidebar: svg('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M9 5v14"/>'),
  plus: svg('<path d="M12 5v14M5 12h14"/>', 16, 'stroke-width="2.2"'),
  check: svg('<path d="m5 12 5 5L20 7"/>', 14, 'stroke="var(--accent-ink)" stroke-width="3"'),
  checkMuted: svg('<path d="m5 12 5 5L20 7"/>', 16, 'stroke-width="2.2"'),
  slash: svg('<path d="m17 7-10 10"/>', 22, 'stroke="var(--rule)" stroke-width="1.6"'),
  paste: svg('<rect x="8" y="2" width="8" height="4" rx="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/>'),
  sun: svg('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'),
  moon: svg('<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>'),
  auto: svg('<circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor"/>'),
  text: svg('<path d="M4 6h16M4 12h10M4 18h14"/>', 16),
  table: svg('<rect x="3" y="4" width="18" height="16" rx="1"/><path d="M3 10h18M3 15h18M10 4v16"/>', 16),
  image: svg('<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-8 8"/>', 16),
  imageBig: svg('<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-8 8"/>', 28),
  file: svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>', 20),
  link: svg('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>', 16),
  code: svg('<path d="m16 18 6-6-6-6M8 6l-6 6 6 6"/>', 16),
  divider: svg('<path d="M4 12h16"/>', 16),
  open: svg('<path d="M14 5h5v5M19 5l-8 8M19 13v5a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/>', 14),
};

// ---------- DOM helpers ----------

function el<K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Record<string, any> = {}, ...children: (Node | string | null | undefined)[]): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null) continue;
    if (k === "class") e.className = v;
    else if (k === "html") e.innerHTML = v;
    else if (k === "style") e.setAttribute("style", v);
    else if (k === "value") (e as HTMLInputElement).value = String(v);
    else if (k.startsWith("on")) e.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k in e && typeof v !== "string") (e as any)[k] = v;
    else e.setAttribute(k, String(v));
  }
  for (const c of children) if (c != null) e.append(c);
  return e;
}
const $ = (sel: string) => document.querySelector(sel) as HTMLElement;

let toastTimer: number | undefined;
function toast(msg: string): void {
  document.querySelector(".toast")?.remove();
  document.body.append(el("div", { class: "toast", role: "status" }, msg));
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => document.querySelector(".toast")?.remove(), 2800);
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
function parseDay(key: string): Date { const [y, m, d] = key.split("-").map(Number); return new Date(y, m - 1, d); }
function dayLabel(pad: Pad): string {
  if (!pad.date) return pad.title || pad.id;
  const d = parseDay(pad.date), now = new Date();
  const diff = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() - d.getTime()) / 86_400_000);
  return diff === 0 ? "Today" : diff === 1 ? "Yesterday" : DAYS[d.getDay()];
}
function shortDate(pad: Pad): string { if (!pad.date) return ""; const d = parseDay(pad.date); return `${d.getDate()} ${MONTHS[d.getMonth()]}`; }
function longDate(pad: Pad): string {
  if (!pad.date) return "Pinned";
  const d = parseDay(pad.date);
  return `${DAYS[d.getDay()].slice(0, 3)} ${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}
function bytes(n: number): string { return n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(0)} KB` : `${(n / 1048576).toFixed(1)} MB`; }

// ---------- shell ----------

function renderShell(): void {
  const app = $("#app");
  app.replaceChildren(
    el("div", { class: "titlebar" },
      el("div", { class: "group" },
        el("button", { class: "icon-btn", "aria-label": "Toggle sidebar", title: "Toggle sidebar", html: I.sidebar, onClick: () => { state.railOpen = !state.railOpen; $(".rail").classList.toggle("hidden", !state.railOpen); } })),
      el("div", { class: "center" }, "Scratchpad"),
      el("div", { class: "group" },
        el("button", { class: "icon-btn", id: "theme", "aria-label": "Appearance", title: "Appearance", onClick: () => setAppearance(nextAppearance[state.appearance]) }),
        el("button", { class: "icon-btn", "aria-label": "Paste as block", title: "Paste as block (Ctrl+Shift+V)", html: I.paste, onClick: pasteFromClipboard }),
        el("button", { class: "icon-btn", "aria-label": "Insert", title: "Insert block", html: I.plus, onClick: (e: MouseEvent) => openMenu(e.clientX - 180, e.clientY + 16) }),
        el("button", { class: "primary", onClick: openToday }, el("span", { html: I.plus }), "New pad"))),
    el("div", { class: "body" },
      el("nav", { class: `rail${state.railOpen ? "" : " hidden"}`, "aria-label": "Pads" }),
      el("main", { class: "pad-wrap" },
        el("div", { class: "paper" },
          el("section", { class: "sheet", "aria-label": "Pad" }),
          el("aside", { class: "todo", "aria-label": "To-do" })))),
  );
  renderTheme();
}

function setAppearance(a: Appearance): void { state.appearance = a; applyAppearance(a); renderTheme(); }
function renderTheme(): void {
  const b = $("#theme");
  b.innerHTML = state.appearance === "light" ? I.sun : state.appearance === "dark" ? I.moon : I.auto;
  b.title = `Appearance: ${state.appearance} (click to change)`;
}

// ---------- rail ----------

function renderRail(): void {
  const rail = $(".rail");
  const days = state.pads.filter((p) => !p.pinned), pinned = state.pads.filter((p) => p.pinned);
  const item = (pad: Pad) => el("button", { class: `item${state.current?.id === pad.id ? " active" : ""}`, onClick: () => openPad(pad.id) },
    el("span", {}, pad.pinned ? pad.title || pad.id : dayLabel(pad)), el("span", { class: "when" }, shortDate(pad)));
  const c = state.current ? counts(state.current) : { carried: 0, open: 0 };
  const newPinned = el("div", { class: "list" });
  const askTitle = () => {
    const input = el("input", { placeholder: "Pad title, then Enter", "aria-label": "New pad title", style: "margin: 2px 0; height: 32px; padding: 0 10px; border: 1px solid var(--rule); background: var(--cell); outline: none;" });
    input.addEventListener("keydown", async (e) => {
      if (e.key === "Escape") { renderRail(); return; }
      if (e.key !== "Enter" || !input.value.trim()) return;
      const pad: Pad = { ...dailyPad(slugify(input.value)), date: null, title: input.value.trim(), pinned: true };
      await api.savePad(pad);
      state.pads = await api.listPads();
      await openPad(pad.id);
    });
    newPinned.replaceChildren(input);
    input.focus();
  };
  newPinned.append(el("button", { class: "item link", onClick: askTitle }, el("span", {}, "New pinned pad")));
  rail.replaceChildren(
    el("div", {}, el("h3", {}, "Days"), el("div", { class: "list" }, ...days.map(item))),
    el("div", {}, el("h3", {}, "Pinned"), el("div", { class: "list" }, ...pinned.map(item)), newPinned),
    el("div", { class: "foot" },
      el("div", {}, "Carried over", el("span", {}, `${c.carried} open`)),
      el("div", {}, isTauri ? "Store" : "Preview", el("span", {}, isTauri ? "local" : "browser"))),
  );
}

// ---------- pad: header + canvas ----------

function renderPad(): void {
  const pad = state.current;
  const sheet = $(".sheet");
  if (!pad) { sheet.replaceChildren(el("p", { style: "color: var(--muted)" }, "No pad")); return; }
  const title = el("input", { value: pad.title, placeholder: "Title", "aria-label": "Pad title", onInput: (e: Event) => { pad.title = (e.target as HTMLInputElement).value; touch(); } });
  const tag = el("input", { value: pad.tag, placeholder: "tag", "aria-label": "Tag", onInput: (e: Event) => { pad.tag = (e.target as HTMLInputElement).value.replace(/^#/, ""); touch(); } });
  const canvas = el("div", { class: "canvas", id: "canvas" });
  if (!pad.blocks.length) canvas.append(el("div", { class: "hint" }, el("span", { html: I.plus }), "Paste or double-click here"));
  for (const b of pad.blocks) canvas.append(renderBlock(b));
  sizeCanvas(canvas, pad);
  canvas.addEventListener("pointerdown", (e) => { if (e.target === canvas) select(null); });
  canvas.addEventListener("dblclick", (e) => { if (e.target === canvas) insertBlock("text", canvasPoint(e)); });
  canvas.addEventListener("contextmenu", (e) => {
    if (e.target !== canvas) return;
    e.preventDefault();
    state.lastPoint = canvasPoint(e);
    openMenu(e.clientX, e.clientY, state.lastPoint);
  });
  sheet.replaceChildren(
    el("div", { class: "header" },
      el("div", { class: "date" }, el("span", { class: "lbl" }, "DATE"), el("span", { class: "val" }, longDate(pad))),
      el("label", { class: "title" }, title),
      el("label", { class: "tag" }, "#", tag)),
    el("div", { class: "canvas-scroll" }, canvas),
  );
}

function sizeCanvas(canvas: HTMLElement, pad: Pad): void {
  const h = pad.blocks.reduce((m, b) => Math.max(m, b.y + (b.h ?? 240)), 0) + 480;
  const w = pad.blocks.reduce((m, b) => Math.max(m, b.x + b.w), 0) + 240;
  canvas.style.minHeight = `${Math.max(720, h)}px`;
  canvas.style.minWidth = `${Math.max(900, w)}px`;
}

function canvasPoint(e: MouseEvent): { x: number; y: number } {
  const r = $("#canvas").getBoundingClientRect();
  return { x: snap(e.clientX - r.left), y: snap(e.clientY - r.top) };
}

function select(id: string | null): void {
  state.selected = id;
  document.querySelectorAll(".block").forEach((b) => b.classList.toggle("selected", (b as HTMLElement).dataset.id === id));
}

function updateBlock(b: Block): void {
  const pad = state.current!;
  const i = pad.blocks.findIndex((x) => x.id === b.id);
  if (i >= 0) pad.blocks[i] = b;
  touch();
}

function renderBlock(b: Block): HTMLElement {
  const node = el("div", { class: `block ${b.kind}${state.selected === b.id ? " selected" : ""}`, "data-id": b.id, style: `left:${b.x}px;top:${b.y}px;width:${b.w}px` });
  const set = (patch: Partial<Block>) => updateBlock({ ...state.current!.blocks.find((x) => x.id === b.id)!, ...patch });
  const autosize = (t: HTMLTextAreaElement) => { t.style.height = "auto"; t.style.height = `${t.scrollHeight}px`; };
  switch (b.kind) {
    case "text":
    case "code": {
      const t = el("textarea", { rows: 1, value: b.text ?? "", "aria-label": b.kind === "code" ? "Code block" : "Text block", spellcheck: b.kind === "text",
        onInput: () => { autosize(t); set({ text: t.value }); } });
      t.addEventListener("keydown", (e) => {
        if (e.key === "/" && t.value === "" && b.kind === "text") {
          e.preventDefault();
          const r = node.getBoundingClientRect();
          openMenu(r.left, r.top + 32, { x: b.x, y: b.y }, b.id);
        }
      });
      node.append(t);
      queueMicrotask(() => autosize(t));
      break;
    }
    case "table": {
      const rows = b.rows ?? [["", ""], ["", ""]];
      if (b.caption) node.append(el("div", { class: "cap" }, b.caption));
      const table = el("table");
      rows.forEach((row, r) => {
        const tr = el("tr");
        row.forEach((cell, c) => {
          const input = el("input", { value: cell, "aria-label": `Row ${r + 1} column ${c + 1}`, onInput: () => { const cur = state.current!.blocks.find((x) => x.id === b.id)!; cur.rows![r][c] = input.value; touch(); } });
          input.addEventListener("keydown", (e) => {
            if (e.key === "Tab" && !e.shiftKey && r === rows.length - 1 && c === row.length - 1) {
              e.preventDefault();
              const cur = state.current!.blocks.find((x) => x.id === b.id)!;
              cur.rows!.push(Array(row.length).fill(""));
              touch(); rerenderBlock(cur, () => (node.querySelectorAll("input")[rows.length * row.length] as HTMLInputElement)?.focus());
            }
          });
          tr.append(el(r === 0 ? "th" : "td", {}, input));
        });
        table.append(tr);
      });
      table.addEventListener("contextmenu", (e) => {
        e.preventDefault(); e.stopPropagation();
        const cur = state.current!.blocks.find((x) => x.id === b.id)!;
        openMenu(e.clientX, e.clientY, undefined, undefined, [
          { label: "Add row", run: () => { cur.rows!.push(Array(cur.rows![0].length).fill("")); touch(); rerenderBlock(cur); } },
          { label: "Add column", run: () => { cur.rows = cur.rows!.map((r) => [...r, ""]); touch(); rerenderBlock(cur); } },
          { label: "Remove last row", run: () => { if (cur.rows!.length > 1) cur.rows!.pop(); touch(); rerenderBlock(cur); } },
          { label: "Remove last column", run: () => { if (cur.rows![0].length > 1) cur.rows = cur.rows!.map((r) => r.slice(0, -1)); touch(); rerenderBlock(cur); } },
          { label: "Delete block", run: () => deleteBlock(b.id) },
        ]);
      });
      node.append(table);
      break;
    }
    case "image": {
      const img = el("img", { alt: b.caption ?? "Pasted image" });
      const ph = el("div", { class: "ph", html: `${I.imageBig}<span>[IMAGE] ${b.asset ?? ""}</span>` });
      node.append(ph);
      if (b.asset) api.assetSrc(b.asset).then((src) => { if (src) { img.src = src; ph.replaceWith(img); } });
      if (b.caption) node.append(el("div", { class: "caption" }, b.caption));
      break;
    }
    case "file":
      node.append(el("button", { class: "card", onClick: () => b.asset && api.openPath(b.asset).catch((e) => toast(String(e))) },
        el("span", { html: I.file }),
        el("span", { class: "meta" }, el("span", { class: "name" }, b.name ?? "File"), el("span", { class: "sub" }, bytes(b.size ?? 0)))));
      break;
    case "link": {
      const title = el("input", { class: "name", value: b.text ?? "", placeholder: "Title", "aria-label": "Link title", onInput: () => set({ text: title.value }) });
      const url = el("input", { class: "sub", value: b.url ?? "", placeholder: "https://", "aria-label": "Link URL", onInput: () => set({ url: url.value }) });
      node.append(el("div", { class: "card" },
        el("span", { class: "meta" }, title, url),
        el("button", { class: "icon-btn", "aria-label": "Open link", html: I.open, onClick: () => b.url && api.openExternal(b.url) })));
      break;
    }
    case "divider":
      node.append(el("hr"));
      break;
  }
  node.append(...["tl", "tr", "bl", "br"].map((c) => el("span", { class: `handle ${c}`, "aria-hidden": "true" })));
  const resize = el("div", { class: "resize", "aria-hidden": "true" });
  node.append(resize);
  wireDrag(node, b.id, resize);
  node.addEventListener("pointerdown", () => select(b.id));
  node.addEventListener("keydown", (e) => {
    if ((e.key === "Delete" || e.key === "Backspace") && (e.target as HTMLElement).tagName === "DIV") deleteBlock(b.id);
  });
  return node;
}

function rerenderBlock(b: Block, after?: () => void): void {
  const old = document.querySelector(`.block[data-id="${b.id}"]`);
  if (old) old.replaceWith(renderBlock(b));
  after?.();
}

function deleteBlock(id: string): void {
  const pad = state.current!;
  pad.blocks = pad.blocks.filter((b) => b.id !== id);
  touch(); renderPad();
}

/** Drag anywhere on the block that is not an editable control; resize from the right strip. */
function wireDrag(node: HTMLElement, id: string, resize: HTMLElement): void {
  let start: { x: number; y: number; bx: number; by: number; bw: number; mode: "move" | "resize" } | null = null;
  const editable = (t: EventTarget | null) => t instanceof HTMLElement && ["INPUT", "TEXTAREA", "BUTTON", "A"].includes(t.tagName);
  node.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    const b = state.current!.blocks.find((x) => x.id === id)!;
    const mode = e.target === resize ? "resize" : "move";
    if (mode === "move" && editable(e.target)) return;
    start = { x: e.clientX, y: e.clientY, bx: b.x, by: b.y, bw: b.w, mode };
    node.setPointerCapture(e.pointerId);
    node.classList.add("dragging");
    e.preventDefault();
  });
  node.addEventListener("pointermove", (e) => {
    if (!start) return;
    const dx = e.clientX - start.x, dy = e.clientY - start.y;
    if (start.mode === "move") { node.style.left = `${start.bx + dx}px`; node.style.top = `${start.by + dy}px`; }
    else node.style.width = `${Math.max(2 * GRID, start.bw + dx)}px`;
  });
  const end = (e: PointerEvent) => {
    if (!start) return;
    const dx = e.clientX - start.x, dy = e.clientY - start.y;
    const b = state.current!.blocks.find((x) => x.id === id)!;
    const next = start.mode === "move" ? snapBlock({ ...b, x: start.bx + dx, y: start.by + dy }) : snapBlock({ ...b, w: start.bw + dx });
    start = null;
    node.classList.remove("dragging");
    node.style.left = `${next.x}px`; node.style.top = `${next.y}px`; node.style.width = `${next.w}px`;
    if (next.x !== b.x || next.y !== b.y || next.w !== b.w) { updateBlock(next); sizeCanvas($("#canvas"), state.current!); }
    if (next.kind === "text" || next.kind === "code") { const t = node.querySelector("textarea"); if (t) { t.style.height = "auto"; t.style.height = `${t.scrollHeight}px`; } }
  };
  node.addEventListener("pointerup", end);
  node.addEventListener("pointercancel", end);
}

// ---------- insert menu ----------

const KINDS: { kind: BlockKind; label: string; key: string; icon: string }[] = [
  { kind: "text", label: "Text", key: "T", icon: I.text }, { kind: "table", label: "Table", key: "B", icon: I.table },
  { kind: "image", label: "Image", key: "I", icon: I.image }, { kind: "file", label: "File", key: "F", icon: I.file },
  { kind: "link", label: "Link", key: "L", icon: I.link }, { kind: "code", label: "Code", key: "C", icon: I.code },
  { kind: "divider", label: "Divider", key: "D", icon: I.divider },
];

function openMenu(x: number, y: number, at?: { x: number; y: number }, replaceId?: string, custom?: { label: string; run: () => void }[]): void {
  closeMenu();
  const menu = el("div", { class: "menu", role: "menu", id: "menu", style: `left:${Math.min(x, window.innerWidth - 210)}px;top:${Math.min(y, window.innerHeight - 300)}px` });
  const items = custom
    ? custom.map((c) => el("button", { role: "menuitem", onClick: () => { closeMenu(); c.run(); } }, c.label))
    : KINDS.map((k) => el("button", { role: "menuitem", "data-key": k.key, onClick: () => { closeMenu(); choose(k.kind); } },
        el("span", { html: k.icon }), k.label, el("span", { class: "key" }, k.key)));
  if (!custom) {
    const filter = el("div", { class: "hint-row" }, "type to filter, Esc closes");
    menu.append(filter);
  }
  menu.append(...items);
  const choose = (kind: BlockKind) => {
    if (replaceId) { state.current!.blocks = state.current!.blocks.filter((b) => b.id !== replaceId); }
    if (kind === "image" || kind === "file") { pickFile(kind, at); return; }
    insertBlock(kind, at);
  };
  const onKey = (e: KeyboardEvent) => {
    if (e.key === "Escape") { closeMenu(); return; }
    if (custom) return;
    const k = KINDS.find((k) => k.key.toLowerCase() === e.key.toLowerCase() || k.label.toLowerCase().startsWith(e.key.toLowerCase()));
    if (k) { e.preventDefault(); closeMenu(); choose(k.kind); }
  };
  document.addEventListener("keydown", onKey);
  const onDown = (e: Event) => { if (!menu.contains(e.target as Node)) closeMenu(); };
  setTimeout(() => document.addEventListener("pointerdown", onDown), 0);
  (menu as any)._cleanup = () => { document.removeEventListener("keydown", onKey); document.removeEventListener("pointerdown", onDown); };
  document.body.append(menu);
  (items[0] as HTMLElement).focus();
}
function closeMenu(): void { const m = document.getElementById("menu"); if (m) { (m as any)._cleanup?.(); m.remove(); } }

function insertBlock(kind: BlockKind, at?: { x: number; y: number }): Block {
  const pad = state.current!;
  const p = at ?? state.lastPoint ?? nextFreePoint(pad);
  const base = { id: uid(), x: p.x, y: p.y };
  let b: Block;
  switch (kind) {
    case "table": b = { ...base, kind, w: 360, rows: [["", ""], ["", ""]] }; break;
    case "link": b = { ...base, kind, w: 300, text: "", url: "" }; break;
    case "divider": b = { ...base, kind, w: 408 }; break;
    case "code": b = { ...base, kind, w: 408, text: "" }; break;
    default: b = { ...base, kind: "text", w: 408, text: "" };
  }
  b = snapBlock(b);
  pad.blocks.push(b);
  touch(); renderPad(); select(b.id);
  (document.querySelector(`.block[data-id="${b.id}"] textarea, .block[data-id="${b.id}"] input`) as HTMLElement | null)?.focus();
  return b;
}

function pickFile(kind: "image" | "file", at?: { x: number; y: number }): void {
  const input = el("input", { type: "file", accept: kind === "image" ? "image/*" : "*/*", multiple: true, style: "display:none" });
  input.addEventListener("change", async () => {
    const files = Array.from(input.files ?? []).map((f) => ({ name: f.name, type: f.type, blob: f }));
    await place(classify({ files: files as any }), at);
    input.remove();
  });
  document.body.append(input);
  input.click();
}

// ---------- paste and drop ----------

async function place(results: PasteResult[], at?: { x: number; y: number }): Promise<void> {
  const pad = state.current!;
  let p = at ?? state.lastPoint ?? nextFreePoint(pad);
  for (const r of results) {
    const base = { id: uid(), x: p.x, y: p.y };
    let b: Block;
    try {
      switch (r.kind) {
        case "text": b = { ...base, kind: "text", w: 408, text: r.text }; break;
        case "code": b = { ...base, kind: "code", w: 408, text: r.text, language: r.language }; break;
        case "link": b = { ...base, kind: "link", w: 300, text: r.title ?? r.url, url: r.url }; break;
        case "table": b = { ...base, kind: "table", w: Math.min(720, 120 * Math.max(2, r.rows[0].length) + 24), rows: r.rows }; break;
        case "image": {
          const asset = r.file.path ? (await api.importFile(r.file.path)).asset : await api.storeAsset(await bytesOf(r.file), r.ext);
          b = { ...base, kind: "image", w: 300, asset }; break;
        }
        case "file": {
          const imported = r.file.path ? await api.importFile(r.file.path) : { asset: await api.storeAsset(await bytesOf(r.file), r.file.name.split(".").pop() ?? "bin"), name: r.file.name, size: (r.file as any).blob?.size ?? 0 };
          b = { ...base, kind: "file", w: 300, asset: imported.asset, name: imported.name, size: imported.size }; break;
        }
      }
    } catch (e) { toast(`Could not add ${r.kind}: ${e}`); continue; }
    b = snapBlock(b);
    pad.blocks.push(b);
    p = { x: p.x, y: p.y + (r.kind === "image" ? 216 : r.kind === "table" ? 48 * r.rows.length + 24 : 72) };
  }
  state.lastPoint = null;
  touch(); renderPad();
}

async function bytesOf(f: { bytes?: ArrayBuffer; blob?: Blob }): Promise<ArrayBuffer> {
  if (f.bytes) return f.bytes;
  if (f.blob) return f.blob.arrayBuffer();
  throw new Error("no file data");
}

function editing(): boolean {
  const a = document.activeElement;
  return a instanceof HTMLInputElement || a instanceof HTMLTextAreaElement;
}

document.addEventListener("paste", (e) => {
  if (!state.current || !e.clipboardData) return;
  const contents = fromDataTransfer(e.clipboardData);
  const results = classify(contents);
  if (!results.length) return;
  // A plain text paste into a field stays a native paste. Anything else becomes a block.
  if (editing() && results.length === 1 && results[0].kind === "text") return;
  e.preventDefault();
  place(results);
});

async function pasteFromClipboard(): Promise<void> {
  try {
    const items = await navigator.clipboard.read();
    const files: ClipboardContents["files"] = [];
    let plain: string | undefined, html: string | undefined;
    for (const item of items) {
      for (const type of item.types) {
        const blob = await item.getType(type);
        if (type.startsWith("image/")) files.push({ name: `pasted.${type.slice(6)}`, type, blob } as any);
        else if (type === "text/html") html = await blob.text();
        else if (type === "text/plain") plain = await blob.text();
      }
    }
    const results = classify({ plain, html, files: files.length ? files : undefined });
    if (!results.length) toast("Clipboard is empty"); else await place(results);
  } catch {
    toast("Press Ctrl+V on the pad to paste");
  }
}

document.addEventListener("dragover", (e) => e.preventDefault());
document.addEventListener("drop", (e) => {
  e.preventDefault();
  if (!state.current || !e.dataTransfer || isTauri) return;
  const at = canvasPointSafe(e);
  place(classify(fromDataTransfer(e.dataTransfer)), at);
});
function canvasPointSafe(e: MouseEvent): { x: number; y: number } | undefined {
  const c = document.getElementById("canvas");
  if (!c) return undefined;
  const r = c.getBoundingClientRect();
  if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) return undefined;
  return { x: Math.max(0, snap(e.clientX - r.left)), y: Math.max(0, snap(e.clientY - r.top)) };
}

async function wireTauriDrop(): Promise<void> {
  if (!isTauri) return;
  const { getCurrentWebview } = await import("@tauri-apps/api/webview");
  await getCurrentWebview().onDragDropEvent((event) => {
    if (event.payload.type !== "drop" || !state.current) return;
    const { x, y } = event.payload.position;
    const at = canvasPointSafe({ clientX: x, clientY: y } as MouseEvent);
    place(classify({ files: event.payload.paths.map((p) => ({ name: p.split("/").pop() ?? "file", path: p })) }), at);
  });
}

// ---------- to-do column ----------

function renderTodo(): void {
  const pad = state.current;
  const aside = $(".todo");
  if (!pad) { aside.replaceChildren(); return; }
  const c = counts(pad);
  const list = el("ol");
  pad.todos.forEach((t, i) => list.append(renderTodoRow(t, i)));
  aside.replaceChildren(
    el("div", { class: "head" },
      el("button", { class: "clear", "aria-label": "Clear completed", title: "Clear completed", html: I.checkMuted, onClick: () => {
        pad.todos = padded({ ...pad, todos: pad.todos.filter((t) => t.status !== "done") }).todos; touch(); renderTodo();
      } }),
      el("div", { class: "box" }, el("span", {}, "To-do"), el("span", { class: "count" }, `${c.done} / ${c.total}`))),
    list,
    el("button", { class: "carry", onClick: () => { pad.todos.unshift(newTodo()); touch(); renderTodo(); focusTodo(pad.todos[0].id); } },
      el("span", { html: I.plus }), c.open ? `${c.open} open, carried at midnight` : "Add to-do"),
  );
}

function renderTodoRow(t: Todo, i: number): HTMLElement {
  const pad = state.current!;
  const cls = [t.status, t.text === "" ? "empty" : "", isOverdue(t) ? "overdue" : ""].filter(Boolean).join(" ");
  const li = el("li", { class: cls, "data-id": t.id });
  const circle = el("button", { class: "circle", "aria-label": `To-do ${i + 1}: ${t.status}`, onClick: () => { t.status = nextStatus[t.status]; touch(); renderTodo(); } },
    el("span", { html: t.status === "done" ? I.check : t.status === "deferred" ? I.slash : "" }));
  const input = el("input", { value: t.text, "aria-label": `To-do ${i + 1} text`, onInput: () => {
    t.text = input.value;
    li.classList.toggle("empty", t.text === "");
    touch();
  } });
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      const n = newTodo();
      pad.todos.splice(i + 1, 0, n);
      touch(); renderTodo(); focusTodo(n.id);
    } else if (e.key === "Backspace" && input.value === "" && pad.todos.length > TODO_ROWS) {
      e.preventDefault();
      pad.todos.splice(i, 1);
      touch(); renderTodo(); focusTodo(pad.todos[Math.max(0, i - 1)].id);
    } else if (e.key === "ArrowDown" && pad.todos[i + 1]) focusTodo(pad.todos[i + 1].id);
    else if (e.key === "ArrowUp" && pad.todos[i - 1]) focusTodo(pad.todos[i - 1].id);
  });
  li.append(circle, el("span", { class: "dash", "aria-hidden": "true" }), input);
  return li;
}

function focusTodo(id: string): void {
  (document.querySelector(`.todo li[data-id="${id}"] input`) as HTMLInputElement | null)?.focus();
}

// ---------- navigation ----------

async function openPad(id: string): Promise<void> {
  await flush();
  const pad = await api.loadPad(id);
  if (!pad) { toast("Pad not found"); return; }
  state.current = padded(pad);
  state.selected = null;
  renderRail(); renderPad(); renderTodo();
  if (window.innerWidth <= 960) { state.railOpen = false; $(".rail").classList.add("hidden"); }
}

async function openToday(): Promise<void> {
  await flush();
  state.current = padded(await api.todayPad());
  state.pads = await api.listPads();
  renderRail(); renderPad(); renderTodo();
}

document.addEventListener("keydown", (e) => {
  const mod = e.ctrlKey || e.metaKey;
  if (!mod) return;
  if (e.key.toLowerCase() === "n" && !e.shiftKey) { e.preventDefault(); openToday(); }
  else if (e.key.toLowerCase() === "t" && e.shiftKey) { e.preventDefault(); const pad = state.current; if (pad) { pad.todos.unshift(newTodo()); touch(); renderTodo(); focusTodo(pad.todos[0].id); } }
  else if (e.key.toLowerCase() === "v" && e.shiftKey) { e.preventDefault(); pasteFromClipboard(); }
  else if (e.key.toLowerCase() === "d" && !e.shiftKey && editing()) {
    const li = (document.activeElement as HTMLElement).closest(".todo li") as HTMLElement | null;
    if (li) { e.preventDefault(); const t = state.current!.todos.find((x) => x.id === li.dataset.id); if (t) { t.status = nextStatus[t.status]; touch(); renderTodo(); focusTodo(t.id); } }
  }
});

window.addEventListener("beforeunload", () => { if (saveTimer) flush(); });

// ---------- boot ----------

function log(msg: string): void {
  if (isTauri) import("@tauri-apps/api/core").then(({ invoke }) => invoke("debug_log", { msg })).catch(() => {});
  else console.log(msg);
}
window.addEventListener("error", (e) => log(`error: ${e.message} @ ${e.filename}:${e.lineno}`));
window.addEventListener("unhandledrejection", (e) => log(`rejection: ${e.reason}`));

(async () => {
  log("boot");
  applyAppearance(state.appearance);
  renderShell();
  try {
    await openToday();
    log(`opened ${state.current?.id}`);
    await wireTauriDrop();
  } catch (e) {
    log(`boot failed: ${e}`);
    toast(`Could not open the store: ${e}`);
  }
})();
