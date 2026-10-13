// The dot-grid canvas: blocks, selection toolbar, move / resize / rotate, tables with formulas, paste and drop.
import { api } from "./api";
import { cellName, colName, display, evaluate, isFormula } from "./formula";
import { after, full, replay } from "./motion";
import { GRID, normAngle, nextFreePoint, snap, snapBlock, uid, type Block, type BlockKind, type FontFamily } from "./model";
import { classify, type PasteResult } from "./paste";
import { prefs } from "./prefs";
import { cur, state, touch } from "./state";
import { $, closePopover, el, I, menu, popover, toast } from "./ui";

const BAND = 8;
const FONT_STACK: Record<FontFamily, string> = { sans: "var(--font-sans)", serif: "var(--font-serif)", mono: "var(--font-mono)", hand: "var(--font-hand)" };
const FONT_LABEL: Record<FontFamily, string> = { sans: "Sans", serif: "Serif", mono: "Mono", hand: "Hand" };
const KIND_LABEL: Record<BlockKind, string> = { text: "Text", table: "Table", image: "Image", file: "File", link: "Link", code: "Code", divider: "Divider" };
const defaultSize = (f: FontFamily) => (f === "hand" ? 22 : f === "mono" ? 13 : 14);

const find = (id: string) => cur().blocks.find((b) => b.id === id);
const nodeOf = (id: string) => document.querySelector(`.block[data-id="${CSS.escape(id)}"]`) as HTMLElement | null;
const canvasEl = () => $("#canvas");

// ---------- render ----------

export function renderCanvas(): void {
  const scroll = $(".canvas-scroll");
  const pad = state.current;
  if (!scroll || !pad) return;
  const canvas = el("div", { class: "canvas", id: "canvas" });
  if (!pad.blocks.length) {
    const drawing = state.freshSheet === pad.id;
    canvas.append(el("div", { class: `empty${drawing ? " draw" : ""}`, "aria-hidden": "true" },
      el("span", { html: '<svg width="260" height="70" viewBox="0 0 260 70" fill="none"><path class="squiggle" d="M6 48c18-30 34-34 40-18s-14 26-6 12 30-38 46-30-6 34 6 30 22-40 40-36 0 30 14 28 24-30 38-28 4 22 16 22 24-14 40-18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="640"/></svg>' }),
      el("p", {}, "A clean sheet. Paste anything, or double-click the dots to write.")));
    state.freshSheet = null;
  }
  for (const b of pad.blocks) canvas.append(renderBlock(b));
  canvas.append(el("div", { class: "btoolbar", role: "toolbar", "aria-label": "Block tools", hidden: true }));
  sizeCanvas(canvas);
  canvas.addEventListener("pointerdown", (e) => { if (e.target === canvas) select(null); });
  canvas.addEventListener("dblclick", (e) => { if (e.target === canvas) insertBlock("text", pointIn(e)); });
  canvas.addEventListener("contextmenu", (e) => {
    if (e.target !== canvas) return;
    e.preventDefault();
    openInsertMenu({ x: e.clientX, y: e.clientY }, pointIn(e));
  });
  scroll.replaceChildren(canvas);
  state.entering.clear();
  if (state.selected) positionToolbar();
}

export function sizeCanvas(canvas = canvasEl()): void {
  const pad = state.current;
  if (!canvas || !pad) return;
  const h = pad.blocks.reduce((m, b) => Math.max(m, b.y + (b.h ?? 240)), 0) + 480;
  const w = pad.blocks.reduce((m, b) => Math.max(m, b.x + b.w), 0) + 240;
  canvas.style.minHeight = `${Math.max(720, h)}px`;
  canvas.style.minWidth = `${w}px`;
}

export function pointIn(e: { clientX: number; clientY: number }): { x: number; y: number } {
  const r = canvasEl()!.getBoundingClientRect();
  return { x: Math.max(0, snap(e.clientX - r.left)), y: Math.max(0, snap(e.clientY - r.top)) };
}

/** Grid point under a screen position, or undefined when outside the visible canvas. */
export function pointInVisible(e: { clientX: number; clientY: number }): { x: number; y: number } | undefined {
  const c = canvasEl();
  if (!c) return undefined;
  const v = (c.parentElement ?? c).getBoundingClientRect();
  if (e.clientX < v.left || e.clientX > v.right || e.clientY < v.top || e.clientY > v.bottom) return undefined;
  return pointIn(e);
}

function fontCss(b: Block): string {
  const f = b.font ?? (b.kind === "code" ? "mono" : "sans");
  return `font-family:${FONT_STACK[f]};font-size:${b.fontSize ?? defaultSize(f)}px;font-weight:${b.bold ? 700 : 400};font-style:${b.italic ? "italic" : "normal"}`;
}

function place(node: HTMLElement, b: Block): void {
  node.style.left = `${b.x - BAND}px`;
  node.style.top = `${b.y - BAND}px`;
  node.style.width = `${b.w + 2 * BAND}px`;
  node.style.height = b.h && b.kind !== "table" ? `${b.h + 2 * BAND}px` : "";
  node.style.setProperty("--rot", `${b.rotation ?? 0}deg`);
  // Table chrome (formula bar + letters) sits above the table, or below when the table is near the top edge.
  if (b.kind === "table") node.classList.toggle("chrome-below", b.y < CHROME_H + 8);
}
const CHROME_H = 50;

function renderBlock(b: Block): HTMLElement {
  const node = el("div", { class: `block k-${b.kind}${state.selected === b.id ? " selected" : ""}${state.entering.has(b.id) ? " enter" : ""}${b.h ? " sized" : ""}`, "data-id": b.id, tabindex: "-1", "aria-label": `${KIND_LABEL[b.kind]} block` });
  place(node, b);
  const content = el("div", { class: "content", style: fontCss(b) });
  node.append(content);
  fillContent(content, b);
  for (const c of ["tl", "tr", "bl", "br"]) node.append(el("span", { class: `h ${c}`, "data-corner": c, "aria-hidden": "true" }));
  wirePointer(node, b.id);
  if (state.entering.has(b.id) && full()) {
    const ring = el("span", { class: "ripple", "aria-hidden": "true", style: `left:${b.x + Math.min(b.w, 300) / 2 - 60}px;top:${b.y + 20 - 60}px` });
    setTimeout(() => canvasEl()?.append(ring), 0);
    setTimeout(() => ring.remove(), 700);
  }
  return node;
}

export function rerenderBlock(id: string, focusSel?: string): void {
  const b = find(id), old = nodeOf(id);
  if (!b || !old) return;
  const fresh = renderBlock(b);
  old.replaceWith(fresh);
  if (focusSel) (fresh.querySelector(focusSel) as HTMLElement | null)?.focus();
  if (state.selected === id) positionToolbar();
}

function autosize(t: HTMLTextAreaElement): void {
  if (t.closest(".block.sized")) return;
  t.style.height = "auto";
  t.style.height = `${t.scrollHeight}px`;
}

function fillContent(content: HTMLElement, b: Block): void {
  const set = (patch: Partial<Block>) => { Object.assign(find(b.id)!, patch); touch(); };
  switch (b.kind) {
    case "text":
    case "code": {
      const t = el("textarea", { rows: 1, value: b.text ?? "", "aria-label": b.kind === "code" ? "Code" : "Text", spellcheck: b.kind === "text" ? "true" : "false", placeholder: b.kind === "text" ? "Write, or type / for blocks" : "" }) as HTMLTextAreaElement;
      t.addEventListener("input", () => { autosize(t); set({ text: t.value }); });
      t.addEventListener("keydown", (e) => {
        if (e.key === "/" && t.value === "" && b.kind === "text") {
          e.preventDefault();
          const r = t.getBoundingClientRect();
          openInsertMenu({ x: r.left, y: r.top + 28 }, { x: b.x, y: b.y }, b.id);
        }
        if (e.key === "Escape") { t.blur(); nodeOf(b.id)?.focus(); }
      });
      content.append(t);
      queueMicrotask(() => autosize(t));
      break;
    }
    case "table": content.append(renderTable(b)); break;
    case "image": {
      const ph = el("div", { class: "ph", html: `${I.imageBig}<span>${b.asset ? "Loading image" : "[IMAGE]"}</span>` });
      content.append(ph);
      if (b.asset) api.assetSrc(b.asset).then((src) => {
        if (!src) return;
        const img = el("img", { alt: b.caption ?? "Pasted image", draggable: "false" }) as HTMLImageElement;
        img.onload = () => ph.replaceWith(img);
        img.onerror = () => { ph.lastElementChild!.textContent = "Image missing"; };
        img.src = src;
      });
      if (b.caption) content.append(el("div", { class: "caption" }, b.caption));
      break;
    }
    case "file":
      content.append(el("button", { class: "card file-card", "aria-label": `Open ${b.name ?? "file"}`, onClick: () => { if (!moved) b.asset && api.openPath(b.asset).catch((e) => toast(String(e))); } },
        el("span", { class: "ico", html: I.file }),
        el("span", { class: "meta" }, el("span", { class: "name" }, b.name ?? "File"), el("span", { class: "sub" }, bytes(b.size ?? 0)))));
      break;
    case "link": {
      const title = el("input", { class: "name", value: b.text ?? "", placeholder: "Title", "aria-label": "Link title", onInput: () => set({ text: title.value }) }) as HTMLInputElement;
      const url = el("input", { class: "sub", value: b.url ?? "", placeholder: "https://", "aria-label": "Link address", onInput: () => set({ url: url.value }) }) as HTMLInputElement;
      content.append(el("div", { class: "card" }, el("span", { class: "meta" }, title, url),
        el("button", { class: "icon-btn", "aria-label": "Open link", html: I.open, onClick: () => b.url && api.openExternal(b.url) })));
      break;
    }
    case "divider": content.append(el("hr")); break;
  }
}

const bytes = (n: number) => (n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(0)} KB` : `${(n / 1048576).toFixed(1)} MB`);

// ---------- tables ----------

const fitWidth = (texts: string[]) => Math.max(40, Math.min(480, Math.round(Math.max(1, ...texts.map((t) => t.length)) * 7.5 + 20)));

function ensureWidths(b: Block): number[] {
  const cols = Math.max(1, ...(b.rows ?? [[""]]).map((r) => r.length));
  const w = (b.colWidths ?? []).slice(0, cols);
  while (w.length < cols) w.push(Math.max(80, Math.round((b.w || 240) / cols)));
  b.colWidths = w;
  b.w = w.reduce((a, x) => a + x, 0);
  return w;
}

function renderTable(b: Block): HTMLElement {
  const rows = b.rows ?? [["", ""], ["", ""]];
  b.rows = rows;
  const widths = ensureWidths(b);
  const wrap = el("div", { class: "tbl" });
  const addr = el("span", { class: "addr" }, "A1");
  const raw = el("span", { class: "raw" });
  const letters = el("div", { class: "letters", "aria-hidden": "true" });
  widths.forEach((w, c) => {
    const grip = el("span", { class: "colgrip", title: "Drag to size, double-click to fit" });
    letters.append(el("span", { class: "letter", style: `width:${w}px` }, colName(c), grip));
    wireColGrip(grip, b.id, c);
  });
  wrap.append(el("div", { class: "tbl-chrome" }, el("div", { class: "fbar" }, addr, el("span", { class: "fx" }, "fx"), raw), letters));

  const table = el("table", { style: `width:${widths.reduce((a, x) => a + x, 0)}px` });
  table.append(el("colgroup", {}, ...widths.map((w) => el("col", { style: `width:${w}px` }))));
  const inputs: HTMLInputElement[][] = [];
  rows.forEach((row, r) => {
    const tr = el("tr");
    inputs.push([]);
    row.forEach((_, c) => {
      const input = el("input", { "aria-label": `Cell ${cellName(r, c)}`, "data-r": r, "data-c": c }) as HTMLInputElement;
      inputs[r].push(input);
      input.addEventListener("focus", () => { input.value = rows[r][c]; addr.textContent = cellName(r, c); raw.textContent = rows[r][c]; input.classList.remove("num", "err"); select(b.id); });
      input.addEventListener("input", () => { rows[r][c] = input.value; raw.textContent = input.value; touch(); refresh(); });
      input.addEventListener("blur", () => refresh());
      input.addEventListener("keydown", (e) => {
        const last = r === rows.length - 1;
        if ((e.key === "Tab" && !e.shiftKey && last && c === row.length - 1) || (e.key === "Enter" && last)) {
          e.preventDefault();
          rows.push(Array(rows[0].length).fill(""));
          touch();
          rerenderBlock(b.id, `input[data-r="${r + 1}"][data-c="${e.key === "Enter" ? c : 0}"]`);
        } else if (e.key === "Enter") { e.preventDefault(); inputs[r + 1]?.[c]?.focus(); }
        else if (e.key === "Escape") { input.blur(); nodeOf(b.id)?.focus(); }
      });
      const cell = el(r === 0 ? "th" : "td", c === 0 ? { "data-row": r + 1 } : {}, input);
      tr.append(cell);
    });
    table.append(tr);
  });
  const refresh = () => {
    const vals = evaluate(rows);
    inputs.forEach((row, r) => row.forEach((input, c) => {
      if (document.activeElement === input) return;
      const v = vals[r]?.[c];
      if (!v) return;
      input.value = display(v);
      input.classList.toggle("num", v.kind === "num" && (isFormula(rows[r][c]) || r > 0));
      input.classList.toggle("err", v.kind === "error");
      input.classList.toggle("formula", isFormula(rows[r][c]));
    }));
  };
  refresh();
  table.addEventListener("contextmenu", (e) => {
    e.preventDefault(); e.stopPropagation();
    const t = find(b.id)!;
    const redo = () => { touch(); rerenderBlock(b.id); };
    menu([
      { label: "Add row", run: () => { t.rows!.push(Array(t.rows![0].length).fill("")); redo(); } },
      { label: "Add column", run: () => { t.rows = t.rows!.map((r) => [...r, ""]); t.colWidths = [...(t.colWidths ?? []), 100]; redo(); } },
      { label: "Remove last row", run: () => { if (t.rows!.length > 1) t.rows!.pop(); redo(); } },
      { label: "Remove last column", run: () => { if (t.rows![0].length > 1) { t.rows = t.rows!.map((r) => r.slice(0, -1)); t.colWidths = t.colWidths?.slice(0, -1); } redo(); } },
      "sep",
      { label: "Delete table", danger: true, icon: I.trash, run: () => deleteBlock(b.id) },
    ], { x: e.clientX, y: e.clientY });
  });
  wrap.append(table);
  return wrap;
}

function wireColGrip(grip: HTMLElement, id: string, c: number): void {
  let start: { x: number; w: number } | null = null;
  const apply = (w: number) => {
    const node = nodeOf(id);
    const b = find(id)!;
    b.colWidths![c] = w;
    b.w = b.colWidths!.reduce((a, x) => a + x, 0);
    if (!node) return;
    (node.querySelectorAll("col")[c] as HTMLElement).style.width = `${w}px`;
    (node.querySelectorAll(".letter")[c] as HTMLElement).style.width = `${w}px`;
    (node.querySelector("table") as HTMLElement).style.width = `${b.w}px`;
    place(node, b);
    positionToolbar();
  };
  grip.addEventListener("pointerdown", (e) => {
    e.stopPropagation(); e.preventDefault();
    start = { x: e.clientX, w: find(id)!.colWidths![c] };
    grip.setPointerCapture(e.pointerId);
    grip.classList.add("active");
  });
  grip.addEventListener("pointermove", (e) => { if (start) apply(Math.max(40, Math.round(start.w + e.clientX - start.x))); });
  const end = () => { if (!start) return; start = null; grip.classList.remove("active"); touch(); sizeCanvas(); };
  grip.addEventListener("pointerup", end);
  grip.addEventListener("pointercancel", end);
  grip.addEventListener("dblclick", (e) => {
    e.stopPropagation();
    const b = find(id)!;
    const vals = evaluate(b.rows!);
    apply(fitWidth(vals.map((r) => display(r[c] ?? { kind: "empty" }))));
    touch();
  });
}

// ---------- selection and toolbar ----------

export function select(id: string | null): void {
  if (state.selected === id) return;
  state.selected = id;
  document.querySelectorAll(".block").forEach((n) => n.classList.toggle("selected", (n as HTMLElement).dataset.id === id));
  positionToolbar();
}

export function positionToolbar(): void {
  const bar = $(".btoolbar");
  const b = state.selected ? find(state.selected) : null;
  const node = b ? nodeOf(b.id) : null;
  if (!bar) return;
  if (!b || !node) { bar.hidden = true; return; }
  if (bar.dataset.for !== b.id) buildToolbar(bar, b);
  bar.hidden = false;
  const below = node.classList.contains("chrome-below");
  const above = b.kind === "table" && !below ? CHROME_H : 0;
  let top = b.y - BAND - 46 - above;
  if (top < 0) top = b.y + node.offsetHeight - BAND + 6 + (below ? CHROME_H : 0);
  bar.style.left = `${Math.max(0, b.x - BAND)}px`;
  bar.style.top = `${top}px`;
  const ang = bar.querySelector(".angle");
  if (ang) ang.textContent = `${Math.round(b.rotation ?? 0)}°`;
}

function buildToolbar(bar: HTMLElement, b: Block): void {
  bar.dataset.for = b.id;
  const grip = el("button", { class: "tb-btn move", "aria-label": "Move block", title: "Drag to move" , html: I.move });
  wireMoveHandle(grip, b.id);
  const textual = ["text", "code", "table", "link"].includes(b.kind);
  const f = b.font ?? (b.kind === "code" ? "mono" : "sans");
  const fontBtn = textual ? el("button", { class: "tb-btn font", "aria-label": `Font: ${FONT_LABEL[f]} ${b.fontSize ?? defaultSize(f)}`, onClick: () => openFontMenu(fontBtn!, b.id) },
    `${FONT_LABEL[f]} ${b.fontSize ?? defaultSize(f)}`, el("span", { html: I.chevron })) : null;
  const rot = el("button", { class: "tb-btn rotate", "aria-label": "Rotate 15 degrees, drag to rotate freely", title: "Click: +15°. Drag: free. Shift: snap. Double-click: reset" },
    el("span", { html: I.rotate }), el("span", { class: "angle" }, `${Math.round(b.rotation ?? 0)}°`));
  wireRotate(rot, b.id);
  bar.replaceChildren(grip, fontBtn ?? "", rot,
    el("button", { class: "tb-btn", "aria-label": "Duplicate block", title: "Duplicate (Ctrl+D)", html: I.duplicate, onClick: () => duplicateBlock(b.id) }),
    el("span", { class: "tb-sep", "aria-hidden": "true" }),
    el("button", { class: "tb-btn danger", "aria-label": "Delete block", title: "Delete (Del)", onClick: () => deleteBlock(b.id) }, el("span", { html: I.trash }), "Delete"));
}

function openFontMenu(anchor: HTMLElement, id: string): void {
  const b = find(id)!;
  const fam = () => b.font ?? (b.kind === "code" ? "mono" : "sans");
  const apply = () => { touch(); rerenderBlock(id); const bar = $(".btoolbar"); if (bar) { bar.dataset.for = ""; positionToolbar(); } };
  const size = el("span", { class: "size" }, String(b.fontSize ?? defaultSize(fam())));
  const step = (d: number) => { b.fontSize = Math.max(10, Math.min(48, (b.fontSize ?? defaultSize(fam())) + d)); size.textContent = String(b.fontSize); apply(); };
  const box = el("div", { class: "menu fontmenu", role: "menu", "aria-label": "Font" },
    ...(Object.keys(FONT_LABEL) as FontFamily[]).map((f) => el("button", { role: "menuitemradio", "aria-checked": String(fam() === f), class: `fam${fam() === f ? " on" : ""}`, style: `font-family:${FONT_STACK[f]};font-size:${f === "hand" ? 22 : 16}px`,
      onClick: () => { b.font = f; b.fontSize = defaultSize(f); size.textContent = String(b.fontSize); box.querySelectorAll(".fam").forEach((x) => { x.classList.toggle("on", (x as HTMLElement).dataset.f === f); x.setAttribute("aria-checked", String((x as HTMLElement).dataset.f === f)); }); apply(); }, "data-f": f }, FONT_LABEL[f])),
    el("div", { class: "sep" }),
    el("div", { class: "row" }, "Size", el("div", { class: "stepper" },
      el("button", { "aria-label": "Smaller", onClick: () => step(-1) }, "−"), size, el("button", { "aria-label": "Larger", onClick: () => step(1) }, "+"))),
    el("div", { class: "row" },
      el("button", { class: `toggle bold${b.bold ? " on" : ""}`, "aria-label": "Bold", "aria-pressed": String(!!b.bold), onClick: (e: Event) => { b.bold = !b.bold; (e.currentTarget as HTMLElement).classList.toggle("on", b.bold); apply(); } }, "B"),
      el("button", { class: `toggle italic${b.italic ? " on" : ""}`, "aria-label": "Italic", "aria-pressed": String(!!b.italic), onClick: (e: Event) => { b.italic = !b.italic; (e.currentTarget as HTMLElement).classList.toggle("on", b.italic); apply(); } }, "I")));
  popover(box, anchor);
}

// ---------- pointer: move, resize ----------

let moved = false;

function wirePointer(node: HTMLElement, id: string): void {
  node.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    const t = e.target as HTMLElement;
    select(id);
    const corner = t.dataset.corner;
    if (corner) { e.preventDefault(); e.stopPropagation(); startResize(e, node, id, corner); return; }
    const editable = t.closest("input, textarea, button, a, select, .colgrip");
    const b = find(id)!;
    const dragAnywhere = ["image", "divider"].includes(b.kind) || (b.kind === "file" && !!t.closest(".card"));
    if (t === node || (!editable && dragAnywhere) || (b.kind === "file" && t.closest(".card"))) {
      if (t === node || b.kind !== "file") e.preventDefault();
      startMove(e, node, id);
    }
  });
  node.addEventListener("keydown", (e) => {
    if (e.target !== node) return;
    const b = find(id);
    if (!b) return;
    if (e.key === "Delete" || e.key === "Backspace") { e.preventDefault(); deleteBlock(id); }
    const nudge: Record<string, [number, number]> = { ArrowLeft: [-GRID, 0], ArrowRight: [GRID, 0], ArrowUp: [0, -GRID], ArrowDown: [0, GRID] };
    if (nudge[e.key]) { e.preventDefault(); b.x = Math.max(0, b.x + nudge[e.key][0]); b.y = Math.max(0, b.y + nudge[e.key][1]); place(node, b); positionToolbar(); touch(); }
  });
}

function wireMoveHandle(handle: HTMLElement, id: string): void {
  handle.addEventListener("pointerdown", (e) => { const node = nodeOf(id); if (node && e.button === 0) { e.preventDefault(); startMove(e, node, id); } });
}

function startMove(e: PointerEvent, node: HTMLElement, id: string): void {
  const b = find(id)!;
  const sx = e.clientX, sy = e.clientY, bx = b.x, by = b.y;
  let live = false;
  moved = false;
  const onMove = (ev: PointerEvent) => {
    const dx = ev.clientX - sx, dy = ev.clientY - sy;
    if (!live && Math.hypot(dx, dy) < 4) return;
    if (!live) { live = true; moved = true; node.classList.add("dragging"); closePopover(); }
    node.style.setProperty("--tilt", `${Math.max(-2, Math.min(2, -dx / 40))}deg`);
    b.x = Math.max(0, bx + dx); b.y = Math.max(0, by + dy);
    place(node, b);
    positionToolbar();
  };
  const onUp = (ev: PointerEvent) => {
    window.removeEventListener("pointermove", onMove);
    window.removeEventListener("pointerup", onUp);
    if (!live) return;
    node.classList.remove("dragging");
    node.style.removeProperty("--tilt");
    if (!ev.altKey) Object.assign(b, snapBlock(b));
    place(node, b);
    replay(node, "landing");
    after(300, () => node.classList.remove("landing"));
    positionToolbar();
    sizeCanvas();
    touch();
    setTimeout(() => { moved = false; }, 0);
  };
  window.addEventListener("pointermove", onMove);
  window.addEventListener("pointerup", onUp);
}

function startResize(e: PointerEvent, node: HTMLElement, id: string, corner: string): void {
  const b = find(id)!;
  const content = node.querySelector(".content") as HTMLElement;
  const s = { x: e.clientX, y: e.clientY, bx: b.x, by: b.y, w: b.w, h: b.h ?? content.offsetHeight, widths: b.colWidths?.slice() };
  const heightful = ["text", "code", "image"].includes(b.kind);
  const onMove = (ev: PointerEvent) => {
    let dx = ev.clientX - s.x, dy = ev.clientY - s.y;
    if (corner.includes("l")) dx = -dx;
    if (corner.includes("t")) dy = -dy;
    let w = Math.max(48, s.w + dx), h = Math.max(24, s.h + dy);
    if (ev.shiftKey && heightful) { const ratio = s.w / s.h; if (Math.abs(dx) > Math.abs(dy)) h = w / ratio; else w = h * ratio; }
    b.w = Math.round(w);
    if (heightful) b.h = Math.round(h);
    if (corner.includes("l")) b.x = s.bx + (s.w - b.w);
    if (corner.includes("t") && heightful) b.y = s.by + (s.h - (b.h ?? s.h));
    if (b.kind === "table" && s.widths) {
      const k = b.w / s.w;
      b.colWidths = s.widths.map((x) => Math.max(40, Math.round(x * k)));
      b.w = b.colWidths.reduce((a, x) => a + x, 0);
      node.querySelectorAll("col").forEach((c, i) => ((c as HTMLElement).style.width = `${b.colWidths![i]}px`));
      node.querySelectorAll(".letter").forEach((c, i) => ((c as HTMLElement).style.width = `${b.colWidths![i]}px`));
      (node.querySelector("table") as HTMLElement).style.width = `${b.w}px`;
    }
    node.classList.toggle("sized", !!b.h);
    place(node, b);
    positionToolbar();
  };
  const onUp = () => {
    window.removeEventListener("pointermove", onMove);
    window.removeEventListener("pointerup", onUp);
    const snapped = snapBlock(b);
    b.x = snapped.x; b.y = snapped.y;
    if (b.kind !== "table") b.w = snapped.w;
    if (b.h) b.h = Math.max(GRID, snap(b.h));
    place(node, b);
    positionToolbar();
    sizeCanvas();
    touch();
  };
  window.addEventListener("pointermove", onMove);
  window.addEventListener("pointerup", onUp);
}

function wireRotate(btn: HTMLElement, id: string): void {
  btn.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    const b = find(id)!;
    const node = nodeOf(id)!;
    const r = node.getBoundingClientRect();
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const a0 = Math.atan2(e.clientY - cy, e.clientX - cx) * 180 / Math.PI;
    const r0 = b.rotation ?? 0;
    let dragged = false;
    const sx = e.clientX, sy = e.clientY;
    const onMove = (ev: PointerEvent) => {
      if (!dragged && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 4) return;
      dragged = true;
      let a = r0 + Math.atan2(ev.clientY - cy, ev.clientX - cx) * 180 / Math.PI - a0;
      if (ev.shiftKey) a = Math.round(a / 15) * 15;
      b.rotation = normAngle(a);
      place(node, b);
      positionToolbar();
    };
    const onUp = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      if (!dragged) { b.rotation = normAngle(Math.round((r0 + 15) / 15) * 15); node.classList.add("turning"); after(320, () => node.classList.remove("turning")); }
      place(node, b);
      positionToolbar();
      touch();
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
  });
  btn.addEventListener("dblclick", () => {
    const b = find(id)!;
    b.rotation = 0;
    const node = nodeOf(id)!;
    node.classList.add("turning");
    after(320, () => node.classList.remove("turning"));
    place(node, b);
    positionToolbar();
    touch();
  });
}

// ---------- block actions ----------

export function deleteBlock(id: string): void {
  const pad = cur();
  const i = pad.blocks.findIndex((b) => b.id === id);
  if (i < 0) return;
  const b = pad.blocks[i];
  const node = nodeOf(id);
  node?.classList.add("crumple");
  if (state.selected === id) select(null);
  after(300, () => {
    pad.blocks = pad.blocks.filter((x) => x.id !== id);
    node?.remove();
    touch();
    if (!pad.blocks.length) renderCanvas();
  });
  toast(`${KIND_LABEL[b.kind]} deleted`, { label: "Undo", run: () => {
    if (state.current !== pad) return;
    pad.blocks.splice(Math.min(i, pad.blocks.length), 0, b);
    state.entering.add(b.id);
    touch();
    renderCanvas();
    select(b.id);
  } });
}

export function duplicateBlock(id: string): void {
  const b = find(id);
  if (!b) return;
  const copy: Block = { ...structuredClone(b), id: uid(), x: b.x + GRID, y: b.y + GRID };
  cur().blocks.push(copy);
  state.entering.add(copy.id);
  touch();
  renderCanvas();
  select(copy.id);
}

function newBlock(kind: BlockKind, p: { x: number; y: number }): Block {
  const base = { id: uid(), x: p.x, y: p.y };
  const font = prefs.defaultFont;
  switch (kind) {
    case "table": return snapBlock({ ...base, kind, w: 240, rows: [["", ""], ["", ""]], colWidths: [120, 120] });
    case "link": return snapBlock({ ...base, kind, w: 300, text: "", url: "" });
    case "divider": return snapBlock({ ...base, kind, w: 408 });
    case "code": return snapBlock({ ...base, kind, w: 408, text: "" });
    default: return snapBlock({ ...base, kind: "text", w: 408, text: "", ...(font !== "sans" ? { font, fontSize: defaultSize(font) } : {}) });
  }
}

export function insertBlock(kind: BlockKind, at?: { x: number; y: number }, replaceId?: string): void {
  const pad = cur();
  if (replaceId) pad.blocks = pad.blocks.filter((b) => b.id !== replaceId);
  if (kind === "image" || kind === "file") { pickFile(kind, at); return; }
  const b = newBlock(kind, at ?? nextFreePoint(pad));
  pad.blocks.push(b);
  state.entering.add(b.id);
  touch();
  renderCanvas();
  select(b.id);
  (nodeOf(b.id)?.querySelector("textarea, input") as HTMLElement | null)?.focus();
}

const KINDS: { kind: BlockKind; label: string; key: string; icon: string }[] = [
  { kind: "text", label: "Text", key: "T", icon: I.text }, { kind: "table", label: "Table", key: "B", icon: I.table },
  { kind: "image", label: "Image", key: "I", icon: I.image }, { kind: "file", label: "File", key: "F", icon: I.file },
  { kind: "link", label: "Link", key: "L", icon: I.link }, { kind: "code", label: "Code", key: "C", icon: I.code },
  { kind: "divider", label: "Divider", key: "D", icon: I.divider },
];

export function openInsertMenu(screen: { x: number; y: number } | HTMLElement, at?: { x: number; y: number }, replaceId?: string): void {
  menu(KINDS.map((k) => ({ label: k.label, icon: k.icon, key: k.key, run: () => insertBlock(k.kind, at, replaceId) })), screen, screen instanceof HTMLElement ? "end" : "start");
  const list = document.querySelector(".popover .menu") as HTMLElement | null;
  list?.addEventListener("keydown", (e) => {
    const k = KINDS.find((x) => x.key.toLowerCase() === e.key.toLowerCase());
    if (k && !e.ctrlKey && !e.metaKey) { e.preventDefault(); closePopover(); insertBlock(k.kind, at, replaceId); }
  });
}

function pickFile(kind: "image" | "file", at?: { x: number; y: number }): void {
  const input = el("input", { type: "file", accept: kind === "image" ? "image/*" : null, multiple: true, style: "display:none" }) as HTMLInputElement;
  input.addEventListener("change", async () => {
    await placeResults(classify({ files: Array.from(input.files ?? []).map((f) => ({ name: f.name, type: f.type, blob: f })) as any }), at);
    input.remove();
  });
  document.body.append(input);
  input.click();
}

const estWidths = (rows: string[][]) => Array.from({ length: Math.max(...rows.map((r) => r.length)) }, (_, c) => Math.max(60, Math.min(320, fitWidth(rows.map((r) => r[c] ?? "")))));

/** Turns paste results into blocks stacked from `at`, storing files through the API. */
export async function placeResults(results: PasteResult[], at?: { x: number; y: number }): Promise<void> {
  const pad = cur();
  let p = at ?? nextFreePoint(pad);
  let last: string | null = null;
  for (const r of results) {
    const base = { id: uid(), x: p.x, y: p.y };
    let b: Block;
    try {
      switch (r.kind) {
        case "text": b = { ...base, kind: "text", w: 408, text: r.text }; break;
        case "code": b = { ...base, kind: "code", w: 408, text: r.text, language: r.language }; break;
        case "link": b = { ...base, kind: "link", w: 300, text: r.title ?? r.url, url: r.url }; if (!r.title) titleLater(b.id, r.url); break;
        case "table": { const colWidths = estWidths(r.rows); b = { ...base, kind: "table", w: colWidths.reduce((a, x) => a + x, 0), rows: r.rows, colWidths }; break; }
        case "image": {
          const asset = r.file.path ? (await api.importFile(r.file.path)).asset : await api.storeAsset(await bytesOf(r.file), r.ext);
          b = { ...base, kind: "image", w: 300, asset }; break;
        }
        case "file": {
          const f: any = r.file;
          const imported = f.path ? await api.importFile(f.path) : { asset: await api.storeAsset(await bytesOf(f), f.name.split(".").pop() ?? "bin"), name: f.name, size: f.blob?.size ?? 0 };
          b = { ...base, kind: "file", w: 300, asset: imported.asset, name: imported.name, size: imported.size }; break;
        }
      }
    } catch (e) { toast(`Could not add ${r.kind}: ${e}`); continue; }
    b = snapBlock(b);
    pad.blocks.push(b);
    state.entering.add(b.id);
    last = b.id;
    p = { x: p.x, y: p.y + (r.kind === "image" ? 216 : r.kind === "table" ? 32 * r.rows.length + 48 : 96) };
  }
  touch();
  renderCanvas();
  if (last) select(last);
}

async function bytesOf(f: { bytes?: ArrayBuffer; blob?: Blob }): Promise<ArrayBuffer> {
  if (f.bytes) return f.bytes;
  if (f.blob) return f.blob.arrayBuffer();
  throw new Error("no file data");
}

function titleLater(blockId: string, url: string): void {
  api.fetchTitle(url).then((title) => {
    const b = state.current?.blocks.find((x) => x.id === blockId);
    if (!title || !b || b.text !== url) return;
    b.text = title; touch(); rerenderBlock(b.id);
  }).catch(() => {});
}

/** A dropped to-do becomes a text block at that point. */
export function textBlockAt(text: string, at: { x: number; y: number }): void {
  const b = snapBlock({ id: uid(), kind: "text", x: at.x, y: at.y, w: 408, text });
  cur().blocks.push(b);
  state.entering.add(b.id);
  touch();
  renderCanvas();
  select(b.id);
}
