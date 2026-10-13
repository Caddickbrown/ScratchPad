import "@fontsource/ibm-plex-sans/latin-400.css";
import "@fontsource/ibm-plex-sans/latin-500.css";
import "@fontsource/ibm-plex-sans/latin-600.css";
import "@fontsource/ibm-plex-sans/latin-700.css";
import "@fontsource/ibm-plex-sans/latin-400-italic.css";
import "@fontsource/ibm-plex-serif/latin-400.css";
import "@fontsource/ibm-plex-serif/latin-600.css";
import "@fontsource/ibm-plex-serif/latin-400-italic.css";
import "@fontsource/ibm-plex-mono/latin-400.css";
import "@fontsource/ibm-plex-mono/latin-500.css";
import "@fontsource/ibm-plex-mono/latin-600.css";
import "@fontsource/caveat/latin-500.css";
import "@fontsource/caveat/latin-700.css";

import { api, isTauri } from "./api";
import { deleteBlock, duplicateBlock, openInsertMenu, placeResults, pointInVisible, renderCanvas, select } from "./canvas";
import { openExport, openSearch, openSettings, renderThemeButton } from "./dialogs";
import { openDatePicker, renderHeader } from "./header";
import { applyAppearance, applyWhimsy } from "./motion";
import { classify, fromDataTransfer, type ClipboardContents } from "./paste";
import { prefs, setPref, type Appearance } from "./prefs";
import { renderRail } from "./sidebar";
import { duplicateSheet, flush, newSheetOn, newSheetToday, openToday, state, view } from "./state";
import { focusBlank, renderTodos } from "./todos";
import { $, editing, el, I, menu, toast } from "./ui";

// ---------- shell ----------

function renderShell(): void {
  const newBtn = el("button", { class: "primary split-main", onClick: () => newSheetToday() }, el("span", { html: I.plus }), "New sheet");
  const more = el("button", { class: "primary split-more", "aria-label": "New sheet options", "aria-haspopup": "menu", html: I.chevron,
    onClick: () => menu([
      { label: "New sheet today", icon: I.newSheet, key: "Ctrl N", run: () => newSheetToday() },
      { label: "New sheet on a date…", icon: I.calendar, run: () => openDatePicker(more, "create") },
      { label: "New pinned sheet", icon: I.pin, run: () => newSheetOn(null) },
      "sep",
      { label: "Duplicate this sheet", icon: I.duplicate, run: () => duplicateSheet() },
    ], more, "end") });
  const insertBtn = el("button", { class: "icon-btn", "aria-label": "Insert block", title: "Insert block", html: I.insert, onClick: () => openInsertMenu(insertBtn) });
  const gear = el("button", { class: "icon-btn", "aria-label": "Settings", title: "Settings", html: I.gear, onClick: () => openSettings(gear) });
  $("#app")!.replaceChildren(
    el("header", { class: "titlebar" },
      el("div", { class: "group" },
        el("button", { class: "icon-btn", "aria-label": "Toggle sidebar", title: "Toggle sidebar", html: I.sidebar, onClick: () => toggleRail() }),
        el("span", { class: "brand" }, "Scratchpad")),
      el("div", { class: "group" },
        el("button", { class: "searchbox", "aria-label": "Search, Ctrl K", onClick: openSearch }, el("span", { html: I.search }), el("span", {}, "Search sheets"), el("span", { class: "kbd" }, "Ctrl K")),
        el("span", { class: "vsep", "aria-hidden": "true" }),
        el("button", { class: "icon-btn", "aria-label": "Export", title: "Export (Ctrl E)", html: I.export, onClick: () => openExport() }),
        el("button", { class: "icon-btn", id: "theme", onClick: () => cycleTheme() }),
        insertBtn,
        gear,
        el("div", { class: "split" }, newBtn, more))),
    el("div", { class: "body" },
      el("nav", { class: `rail${prefs.railOpen ? "" : " hidden"}`, "aria-label": "Sheets" }),
      el("main", { class: "pad-wrap" },
        el("div", { class: "paper" },
          el("section", { class: "sheet", "aria-label": "Sheet" }, el("div", { class: "header" }), el("div", { class: "canvas-scroll" })),
          el("aside", { class: "todo", "aria-label": "To-do" })))),
  );
  renderThemeButton();
}

function toggleRail(): void {
  setPref("railOpen", !prefs.railOpen);
  $(".rail")?.classList.toggle("hidden", !prefs.railOpen);
}

function cycleTheme(): void {
  const next: Record<Appearance, Appearance> = { system: "light", light: "dark", dark: "system" };
  applyAppearance(next[prefs.appearance], true);
  renderThemeButton();
}

view.rail = renderRail;
view.sheet = () => { renderHeader(); renderCanvas(); };
view.todos = renderTodos;

// ---------- paste and drop ----------

document.addEventListener("paste", (e) => {
  if (!state.current || !e.clipboardData) return;
  const results = classify(fromDataTransfer(e.clipboardData));
  if (!results.length) return;
  // Plain text pasted into a field stays a native paste. Anything else becomes a block.
  if (editing() && results.length === 1 && results[0].kind === "text") return;
  if (editing() && (document.activeElement as HTMLElement).closest(".todo, .header, .popover, .dialog")) return;
  e.preventDefault();
  placeResults(results);
});

async function pasteFromClipboard(): Promise<void> {
  try {
    const items = await navigator.clipboard.read();
    const files: NonNullable<ClipboardContents["files"]> = [];
    let plain: string | undefined, html: string | undefined;
    for (const item of items) for (const type of item.types) {
      const blob = await item.getType(type);
      if (type.startsWith("image/")) files.push({ name: `pasted.${type.slice(6)}`, type, blob } as any);
      else if (type === "text/html") html = await blob.text();
      else if (type === "text/plain") plain = await blob.text();
    }
    const results = classify({ plain, html, files: files.length ? files : undefined });
    if (!results.length) toast("The clipboard is empty"); else await placeResults(results);
  } catch { toast("Press Ctrl+V on the sheet to paste"); }
}

document.addEventListener("dragover", (e) => e.preventDefault());
document.addEventListener("drop", (e) => {
  e.preventDefault();
  if (!state.current || !e.dataTransfer || isTauri) return;
  placeResults(classify(fromDataTransfer(e.dataTransfer)), pointInVisible(e));
});

async function wireTauriDrop(): Promise<void> {
  if (!isTauri) return;
  const { getCurrentWebview } = await import("@tauri-apps/api/webview");
  await getCurrentWebview().onDragDropEvent((event) => {
    if (event.payload.type !== "drop" || !state.current) return;
    const { x, y } = event.payload.position;
    placeResults(classify({ files: event.payload.paths.map((p) => ({ name: p.split("/").pop() ?? "file", path: p })) }), pointInVisible({ clientX: x, clientY: y }));
  });
}

// ---------- keyboard ----------

document.addEventListener("keydown", (e) => {
  const mod = e.ctrlKey || e.metaKey;
  const k = e.key.toLowerCase();
  if (document.querySelector(".backdrop:not(.leaving)")) return;
  if (mod && k === "n" && !e.shiftKey) { e.preventDefault(); newSheetToday(); }
  else if (mod && k === "k") { e.preventDefault(); openSearch(); }
  else if (mod && k === "e") { e.preventDefault(); openExport(); }
  else if (mod && e.shiftKey && k === "t") { e.preventDefault(); focusBlank(); }
  else if (mod && e.shiftKey && k === "v") { e.preventDefault(); pasteFromClipboard(); }
  else if (mod && k === "d" && state.selected && !editing()) { e.preventDefault(); duplicateBlock(state.selected); }
  else if ((e.key === "Delete" || e.key === "Backspace") && state.selected && !editing() && !document.querySelector(".popover")) { e.preventDefault(); deleteBlock(state.selected); }
  else if (e.key === "Escape" && state.selected && !document.querySelector(".popover")) {
    if (editing()) (document.activeElement as HTMLElement).blur(); else select(null);
  }
});

window.addEventListener("beforeunload", () => { flush(); });
window.addEventListener("blur", () => { flush(); });

// ---------- boot ----------

(async () => {
  applyAppearance(prefs.appearance);
  applyWhimsy();
  renderShell();
  window.addEventListener("error", (e) => api.log(`error: ${e.message} @ ${e.filename}:${e.lineno}`));
  window.addEventListener("unhandledrejection", (e) => api.log(`rejection: ${e.reason}`));
  api.log("boot");
  try {
    await openToday();
    api.log(`opened ${state.current?.id}`);
    await wireTauriDrop();
  } catch (e) {
    api.log(`boot failed: ${e}`);
    toast(`Could not open the store: ${e}`);
  }
})();
