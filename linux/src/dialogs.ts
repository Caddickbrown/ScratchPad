// Export dialog, settings popover, search palette.
import { toPng } from "html-to-image";
import { api } from "./api";
import { applyAppearance, applyWhimsy, moving } from "./motion";
import { everythingMarkdown, todosMarkdown } from "./markdown";
import { dayLabel, filled, matches, tagCounts, todayKey, type FontFamily, type Pad } from "./model";
import { prefs, setPref, type Appearance, type Whimsy } from "./prefs";
import { flush, openPad, refreshPads, state, view } from "./state";
import { el, I, popover, segmented, toast } from "./ui";

// ---------- modal shell ----------

function modal(label: string, body: HTMLElement): { close: () => void; root: HTMLElement } {
  const backdrop = el("div", { class: "backdrop" });
  const dialog = el("div", { class: "dialog", role: "dialog", "aria-modal": "true", "aria-label": label }, body);
  backdrop.append(dialog);
  const close = () => {
    document.removeEventListener("keydown", onKey, true);
    backdrop.classList.add("leaving");
    setTimeout(() => backdrop.remove(), moving() ? 140 : 0);
  };
  const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); close(); } };
  document.addEventListener("keydown", onKey, true);
  backdrop.addEventListener("pointerdown", (e) => { if (e.target === backdrop) close(); });
  document.body.append(backdrop);
  return { close, root: dialog };
}

// ---------- export ----------

type Mode = "image" | "markdown" | "all";
const stamp = () => todayKey();
const safe = (s: string) => (s.trim() || "untitled-sheet").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

/** Clones the visible paper into an offscreen, themed, full-height copy for capture. */
function captureNode(theme: "light" | "dark" | "app", withTodos: boolean): { node: HTMLElement; dispose: () => void } {
  const paper = document.querySelector(".paper") as HTMLElement;
  const clone = paper.cloneNode(true) as HTMLElement;
  const src = paper.querySelectorAll("input, textarea");
  clone.querySelectorAll("input, textarea").forEach((n, i) => {
    const v = (src[i] as HTMLInputElement).value;
    if (n instanceof HTMLTextAreaElement) n.textContent = v; else n.setAttribute("value", v);
  });
  clone.querySelectorAll(".selected").forEach((n) => n.classList.remove("selected"));
  clone.querySelectorAll(".btoolbar, .stamp-slot, .todo-tools, .todo-foot, li.blank, .grip, .ripple, .chip.add, .chip button, .header .cal").forEach((n) => n.remove());
  if (!withTodos) clone.querySelector(".todo")?.remove();
  const scroll = clone.querySelector(".canvas-scroll") as HTMLElement | null;
  if (scroll) { scroll.style.overflow = "visible"; scroll.style.flex = "none"; }
  const canvas = clone.querySelector(".canvas") as HTMLElement | null;
  let contentRight = 480;
  if (canvas && state.current) {
    const bottom = state.current.blocks.reduce((m, b) => Math.max(m, b.y + (b.h ?? (document.querySelector(`.block[data-id="${CSS.escape(b.id)}"]`) as HTMLElement | null)?.offsetHeight ?? 120)), 0);
    const right = state.current.blocks.reduce((m, b) => Math.max(m, b.x + b.w), 0);
    canvas.style.minHeight = `${Math.max(360, bottom + 48)}px`;
    contentRight = Math.max(480, right + 48);
    canvas.style.minWidth = `${contentRight}px`;
    canvas.style.height = "auto";
  }
  const resolved = theme === "app" ? (document.documentElement.dataset.theme ?? (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")) : theme;
  const host = el("div", { class: `capture theme-${resolved}`, "aria-hidden": "true" });
  clone.classList.remove("sheet-in");
  // An explicit width: flex children like the title field collapse to nothing under max-content.
  const todoW = withTodos ? 340 : 0;
  clone.style.width = `${Math.max(withTodos ? paper.offsetWidth : paper.offsetWidth - 340, contentRight + 50 + todoW, 760)}px`;
  host.append(clone);
  document.body.append(host);
  return { node: clone, dispose: () => host.remove() };
}

async function sheetPng(theme: "light" | "dark" | "app", scale: number, withTodos: boolean): Promise<string> {
  const { node, dispose } = captureNode(theme, withTodos);
  try {
    await document.fonts.ready;
    return await toPng(node, { pixelRatio: scale, cacheBust: false, imagePlaceholder: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" });
  } finally { dispose(); }
}

const dataUrlBytes = (url: string) => Uint8Array.from(atob(url.split(",")[1]), (c) => c.charCodeAt(0));

export function openExport(initial: Mode = "image"): void {
  if (!state.current) return;
  let mode: Mode = initial;
  const opt = { theme: "app" as "light" | "dark" | "app", scale: 2, todos: true, mdScope: "sheet" as "sheet" | "today" | "open", done: false, deferred: true, format: "archive" as "archive" | "md" | "json", tag: "" };
  const nav = el("nav", { class: "ex-nav", "aria-label": "Export type" });
  const pane = el("div", { class: "ex-pane" });
  const foot = el("div", { class: "ex-foot" });
  const { close, root } = modal("Export", el("div", { class: "export" }, nav, el("div", { class: "ex-main" }, pane, foot)));
  root.classList.add("wide");

  const MODES: { id: Mode; title: string; sub: string }[] = [
    { id: "image", title: "Sheet as image", sub: "PNG, light or dark" },
    { id: "markdown", title: "To-dos as Markdown", sub: "Checkbox list to paste anywhere" },
    { id: "all", title: "Everything, one file", sub: "Backup, or move to another device" },
  ];
  const drawNav = () => nav.replaceChildren(el("h2", {}, "Export"), ...MODES.map((m) =>
    el("button", { class: `ex-mode${m.id === mode ? " on" : ""}`, "aria-pressed": String(m.id === mode), onClick: () => { mode = m.id; draw(); } },
      el("span", { class: "t" }, m.title), el("span", { class: "s" }, m.sub))));

  let previewTimer: number | undefined;
  const preview = (img: HTMLImageElement) => {
    window.clearTimeout(previewTimer);
    img.classList.add("busy");
    previewTimer = window.setTimeout(async () => {
      try { img.src = await sheetPng(opt.theme, 0.6, opt.todos); } catch (e) { api.log(`preview failed: ${e}`); }
      img.classList.remove("busy");
    }, 120);
  };

  const sheetsFor = (scope: typeof opt.mdScope): Pad[] => {
    const all = state.pads.map((p) => (p.id === state.current!.id ? state.current! : p));
    if (scope === "sheet") return [state.current!];
    if (scope === "today") return all.filter((p) => p.date === todayKey());
    return all;
  };
  const mdText = () => todosMarkdown(sheetsFor(opt.mdScope), { includeDone: opt.done, includeDeferred: opt.deferred, openOnly: opt.mdScope === "open" });
  const allSheets = () => state.pads.map((p) => (p.id === state.current!.id ? state.current! : p)).filter((p) => !opt.tag || p.tags.includes(opt.tag));

  const button = (label: string, run: () => Promise<void> | void, primary = false) =>
    el("button", { class: primary ? "primary" : "ghost", onClick: async (e: Event) => {
      const b = e.currentTarget as HTMLButtonElement;
      b.disabled = true;
      try { await run(); } catch (err) { toast(`Export failed: ${err}`); } finally { b.disabled = false; }
    } }, label);

  const check = (label: string, value: boolean, set: (v: boolean) => void) =>
    el("label", { class: "check" }, el("input", { type: "checkbox", checked: value, onChange: (e: Event) => set((e.target as HTMLInputElement).checked) }), label);

  const draw = () => {
    drawNav();
    const cancel = el("button", { class: "ghost cancel", onClick: close }, "Cancel");
    if (mode === "image") {
      const img = el("img", { class: "ex-preview", alt: "Preview of the exported sheet" }) as HTMLImageElement;
      pane.replaceChildren(
        el("div", { class: "ex-row" },
          el("div", { class: "field" }, el("span", {}, "Theme"), segmented("Theme", [{ value: "light", label: "Light" }, { value: "dark", label: "Dark" }, { value: "app", label: "Match app" }], opt.theme, (v) => { opt.theme = v; preview(img); })),
          el("label", { class: "field" }, el("span", {}, "Size"), el("select", { onChange: (e: Event) => { opt.scale = Number((e.target as HTMLSelectElement).value); } },
            el("option", { value: "2", selected: opt.scale === 2 || null }, "2x, sharp on HiDPI"), el("option", { value: "1", selected: opt.scale === 1 || null }, "1x"), el("option", { value: "3", selected: opt.scale === 3 || null }, "3x, for printing"))),
          check("Include to-do column", opt.todos, (v) => { opt.todos = v; preview(img); })),
        el("figure", { class: "ex-figure" }, img),
        el("p", { class: "hint" }, "The whole sheet, not just what is on screen. Selection outlines and handles are left out."));
      preview(img);
      const name = `${safe(state.current!.title)}-${state.current!.date ?? "pinned"}.png`;
      foot.replaceChildren(cancel,
        button("Copy", async () => {
          const url = await sheetPng(opt.theme, opt.scale, opt.todos);
          const blob = await (await fetch(url)).blob();
          await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
          toast("Image copied");
        }),
        button("Save PNG", async () => {
          const url = await sheetPng(opt.theme, opt.scale, opt.todos);
          if (await api.saveFile(name, dataUrlBytes(url), { name: "PNG image", extensions: ["png"] })) { close(); toast("Image saved"); }
        }, true));
    } else if (mode === "markdown") {
      const pre = el("pre", { class: "ex-md" });
      const update = () => { pre.textContent = mdText(); };
      pane.replaceChildren(
        el("div", { class: "ex-row" },
          el("label", { class: "field" }, el("span", {}, "Which to-dos"), el("select", { onChange: (e: Event) => { opt.mdScope = (e.target as HTMLSelectElement).value as any; update(); } },
            el("option", { value: "sheet", selected: opt.mdScope === "sheet" || null }, "This sheet"),
            el("option", { value: "today", selected: opt.mdScope === "today" || null }, "All of today's sheets"),
            el("option", { value: "open", selected: opt.mdScope === "open" || null }, "Every open to-do"))),
          check("Include done", opt.done, (v) => { opt.done = v; update(); }),
          check("Include deferred", opt.deferred, (v) => { opt.deferred = v; update(); })),
        pre,
        el("p", { class: "hint" }, "Standard task-list syntax, so it pastes into GitHub, Obsidian or Notion as working checkboxes."));
      update();
      foot.replaceChildren(cancel,
        button("Copy", async () => { await navigator.clipboard.writeText(mdText()); toast("Markdown copied"); }),
        button("Save .md", async () => { if (await api.saveFile(`todos-${stamp()}.md`, mdText(), { name: "Markdown", extensions: ["md"] })) { close(); toast("Markdown saved"); } }, true));
    } else {
      const summary = el("div", { class: "ex-summary" });
      const updateSummary = () => {
        const s = allSheets();
        const att = s.reduce((n, p) => n + p.blocks.filter((b) => b.asset).length, 0);
        summary.replaceChildren(
          el("span", {}, el("strong", {}, String(s.length)), " sheets"),
          el("span", {}, el("strong", {}, String(s.reduce((n, p) => n + p.todos.filter(filled).length, 0))), " to-dos"),
          el("span", {}, el("strong", {}, String(att)), " attachments"),
          el("span", { class: "note" }, opt.format === "archive" ? "Attachments included" : opt.format === "md" ? "Images become links" : "Attachments not included"));
      };
      const FORMATS = [
        { id: "archive", title: "Scratchpad archive", ext: ".scratchpad", sub: "Every sheet, block, to-do and attachment in one file. Import it on any device." },
        { id: "md", title: "Markdown", ext: ".md", sub: "One readable document, newest sheet first. Tables stay tables; images become links." },
        { id: "json", title: "JSON", ext: ".json", sub: "The raw sheet data without attachments, for scripts." },
      ] as const;
      const fset = el("fieldset", { class: "formats" }, el("legend", {}, "Format"), ...FORMATS.map((f) =>
        el("label", { class: `fmt${opt.format === f.id ? " on" : ""}` },
          el("input", { type: "radio", name: "fmt", checked: opt.format === f.id, onChange: () => { opt.format = f.id; fset.querySelectorAll(".fmt").forEach((x, i) => x.classList.toggle("on", FORMATS[i].id === f.id)); updateSummary(); saveBtn.textContent = `Save ${f.ext}`; } }),
          el("span", { class: "body" }, el("span", { class: "t" }, f.title, el("span", { class: "ext" }, f.ext)), el("span", { class: "s" }, f.sub)))));
      const tags = tagCounts(state.pads);
      pane.replaceChildren(fset,
        el("label", { class: "field" }, el("span", {}, "Sheets"), el("select", { onChange: (e: Event) => { opt.tag = (e.target as HTMLSelectElement).value; updateSummary(); } },
          el("option", { value: "" }, "All sheets"), ...tags.map((t) => el("option", { value: t.tag, selected: opt.tag === t.tag || null }, `Only #${t.tag} (${t.count})`)))),
        summary);
      updateSummary();
      const saveBtn = button(`Save ${FORMATS.find((f) => f.id === opt.format)!.ext}`, async () => {
        await flush();
        const base = `scratchpad-${opt.tag ? `${opt.tag}-` : ""}${stamp()}`;
        let ok = false;
        if (opt.format === "archive") ok = await api.saveFile(`${base}.scratchpad`, await api.archiveJson(opt.tag || undefined), { name: "Scratchpad archive", extensions: ["scratchpad"] });
        else if (opt.format === "md") ok = await api.saveFile(`${base}.md`, everythingMarkdown(allSheets()), { name: "Markdown", extensions: ["md"] });
        else ok = await api.saveFile(`${base}.json`, JSON.stringify(allSheets(), null, 2), { name: "JSON", extensions: ["json"] });
        if (ok) { close(); toast("Export saved"); }
      }, true);
      foot.replaceChildren(cancel, saveBtn);
    }
  };
  draw();
}

// ---------- settings ----------

export function openSettings(anchor: HTMLElement): void {
  const fonts: { value: FontFamily; label: string }[] = [{ value: "sans", label: "Sans" }, { value: "serif", label: "Serif" }, { value: "mono", label: "Mono" }, { value: "hand", label: "Hand" }];
  const root = el("span", { class: "mono small" }, "…");
  api.storeRoot().then((r) => (root.textContent = r));
  const box = el("div", { class: "settings", role: "dialog", "aria-label": "Settings" },
    el("div", { class: "field" }, el("span", {}, "Appearance"), segmented<Appearance>("Appearance", [{ value: "system", label: "System" }, { value: "light", label: "Light" }, { value: "dark", label: "Dark" }], prefs.appearance, (v) => { applyAppearance(v, true); renderThemeButton(); })),
    el("div", { class: "field" }, el("span", {}, "Whimsy"), segmented<Whimsy>("Whimsy", [{ value: "full", label: "Full" }, { value: "subtle", label: "Subtle" }, { value: "off", label: "Off" }], prefs.whimsy, (v) => applyWhimsy(v))),
    el("p", { class: "hint" }, "Your system's Reduce motion setting turns whimsy off."),
    el("label", { class: "field" }, el("span", {}, "Default font for new text"), el("select", { onChange: (e: Event) => setPref("defaultFont", (e.target as HTMLSelectElement).value as FontFamily) },
      ...fonts.map((f) => el("option", { value: f.value, selected: prefs.defaultFont === f.value || null }, f.label)))),
    el("div", { class: "sep" }),
    el("button", { class: "ghost wide", onClick: importArchive }, "Import archive…"),
    el("div", { class: "field" }, el("span", {}, "Stored in"), root));
  popover(box, anchor, { align: "end" });
}

async function importArchive(): Promise<void> {
  try {
    const json = await api.openTextFile({ name: "Scratchpad archive", extensions: ["scratchpad", "json"] });
    if (json == null) return;
    await flush();
    const r = await api.importArchiveJson(json);
    await refreshPads();
    view.rail();
    toast(`Imported ${r.sheets} sheet${r.sheets === 1 ? "" : "s"} and ${r.assets} attachment${r.assets === 1 ? "" : "s"}`);
  } catch (e) { toast(String(e)); }
}

export function renderThemeButton(): void {
  const b = document.getElementById("theme");
  if (!b) return;
  const a = prefs.appearance;
  const icon = a === "light" ? I.sun : a === "dark" ? I.moon : I.auto;
  b.replaceChildren(el("span", { class: `theme-icon${moving() ? " swap" : ""}`, html: icon }));
  b.setAttribute("aria-label", `Appearance: ${a}`);
  b.title = `Appearance: ${a}. Click to change`;
}

// ---------- search ----------

export function openSearch(): void {
  const input = el("input", { placeholder: "Search sheets, blocks, tags and to-dos", "aria-label": "Search" }) as HTMLInputElement;
  const results = el("div", { class: "results", role: "listbox" });
  const { close } = modal("Search", el("div", { class: "search" }, el("div", { class: "field-row" }, el("span", { html: I.search }), input), results));
  document.querySelector(".backdrop")?.classList.add("top");
  const snippet = (p: Pad, q: string) => {
    const needle = q.trim().toLowerCase().replace(/^#/, "");
    const texts = [...p.tags.map((t) => `#${t}`), ...p.todos.map((t) => t.text), ...p.blocks.flatMap((b) => [b.text, b.name, b.url, b.caption, ...(b.rows?.flat() ?? [])])];
    const hit = texts.find((t) => t && t.toLowerCase().includes(needle)) ?? "";
    const i = hit.toLowerCase().indexOf(needle);
    const from = Math.max(0, i - 30);
    return (from > 0 ? "…" : "") + hit.slice(from, from + 90).replace(/\n/g, " ");
  };
  const run = () => {
    const q = input.value;
    const pads = state.pads.map((p) => (p.id === state.current?.id ? state.current! : p));
    const hits = q.trim() ? pads.filter((p) => matches(p, q)).slice(0, 20) : [];
    results.replaceChildren(...hits.map((p) => el("button", { role: "option", onClick: () => { close(); openPad(p.id); } },
      el("span", { class: "name" }, `${p.title.trim() || "Untitled sheet"}`, el("span", { class: "when" }, p.date ? dayLabel(p.date) : "Pinned")),
      el("span", { class: "sub" }, snippet(p, q)))));
    if (q.trim() && !hits.length) results.append(el("div", { class: "none" }, "Nothing matches"));
  };
  input.addEventListener("input", run);
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") (results.querySelector("button") as HTMLButtonElement | null)?.click();
    if (e.key === "ArrowDown") { e.preventDefault(); (results.querySelector("button") as HTMLButtonElement | null)?.focus(); }
  });
  results.addEventListener("keydown", (e) => {
    const btns = [...results.querySelectorAll("button")] as HTMLButtonElement[];
    const i = btns.indexOf(document.activeElement as HTMLButtonElement);
    if (e.key === "ArrowDown") { e.preventDefault(); btns[Math.min(btns.length - 1, i + 1)]?.focus(); }
    if (e.key === "ArrowUp") { e.preventDefault(); (i <= 0 ? input : btns[i - 1]).focus(); }
  });
  input.focus();
}
