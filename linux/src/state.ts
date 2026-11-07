// App state, persistence and sheet-level actions. Renderers register themselves in `view`.
import { api } from "./api";
import { after, moving } from "./motion";
import { dayKey, newSheet, todayKey, uid, type Pad } from "./model";
import { prefs } from "./prefs";
import { toast } from "./ui";

export const state = {
  pads: [] as Pad[],
  current: null as Pad | null,
  selected: null as string | null,
  /** Block ids that should play their drop-in once. */
  entering: new Set<string>(),
  /** Set right after New sheet so the empty sheet draws its squiggle. */
  freshSheet: null as string | null,
  /** Set when today's sheet was just created with carried rows, so they hop in. */
  hopSheet: null as string | null,
};

export const view = {
  rail: () => {},
  sheet: () => {},
  todos: () => {},
  all: () => { view.rail(); view.sheet(); view.todos(); },
};

let saveTimer: number | undefined;
let lastWrite: { id: string; at: string } | null = null;
export function touch(): void {
  if (state.current) state.current.updatedAt = new Date().toISOString();
  window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(flush, 400);
}

export async function flush(): Promise<void> {
  // Only a real edit writes: this also runs on losing focus, and writing the copy in memory
  // then would overwrite whatever another device saved to a synced folder.
  if (saveTimer === undefined) return;
  window.clearTimeout(saveTimer);
  saveTimer = undefined;
  const pad = state.current;
  if (!pad) return;
  try { await api.savePad(pad); } catch (e) { toast(`Could not save: ${e}`); return; }
  // The store stamps the file, and this write mustn't look like news from another device.
  lastWrite = { id: pad.id, at: (await api.loadPad(pad.id).catch(() => null))?.updatedAt ?? pad.updatedAt };
  upsert(pad);
  view.rail();
}

export function upsert(pad: Pad): void {
  const i = state.pads.findIndex((p) => p.id === pad.id);
  if (i >= 0) state.pads[i] = pad; else state.pads.unshift(pad);
}

export async function refreshPads(): Promise<void> {
  state.pads = await api.listPads();
  if (state.current) upsert(state.current);
}

export async function openPad(id: string): Promise<void> {
  if (state.current?.id === id) return;
  await flush();
  const pad = state.pads.find((p) => p.id === id) ?? (await api.loadPad(id));
  if (!pad) { toast("That sheet is gone"); return; }
  state.current = structuredClone(pad);
  state.selected = null;
  view.all();
}

export async function openToday(): Promise<void> {
  await flush();
  const pad = await api.todayPad();
  await refreshPads();
  const fresh = Date.now() - Date.parse(pad.createdAt) < 15_000;
  if (fresh && pad.todos.some((t) => t.carriedFrom)) state.hopSheet = pad.id;
  state.current = pad;
  state.selected = null;
  view.all();
}

let lastToday = todayKey();

/** Back in focus: sees what other devices saved, and moves on from yesterday's sheet. */
export async function cameBack(): Promise<void> {
  await flush();
  const today = todayKey();
  const wasToday = lastToday !== today && state.current?.date === lastToday;
  lastToday = today;
  if (wasToday) { await openToday(); return; }
  const id = state.current?.id;
  const fresh = id ? await api.loadPad(id) : null;
  if (state.current?.id !== id || saveTimer !== undefined) return;
  await refreshPads();
  const seen = lastWrite?.id === id ? lastWrite.at : state.current?.updatedAt ?? "";
  if (fresh && state.current && Date.parse(fresh.updatedAt) > Date.parse(seen)) {
    state.current = fresh;
    upsert(fresh);
    view.all();
  } else view.rail();
}

/** Peels the visible paper away (the desk-pad tear-off), then shows `next`. */
async function tearTo(next: Pad, focusTitle = true): Promise<void> {
  const paper = document.querySelector(".paper") as HTMLElement | null;
  if (paper && moving()) {
    const r = paper.getBoundingClientRect();
    const ghost = paper.cloneNode(true) as HTMLElement;
    ghost.classList.add("peel");
    ghost.setAttribute("aria-hidden", "true");
    Object.assign(ghost.style, { position: "fixed", left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px`, margin: "0" });
    document.body.append(ghost);
    after(720, () => ghost.remove());
  }
  state.current = next;
  state.selected = null;
  state.freshSheet = next.blocks.length ? null : next.id;
  upsert(next);
  view.all();
  const p = document.querySelector(".paper");
  if (p && moving()) { p.classList.remove("sheet-in"); void (p as HTMLElement).offsetWidth; p.classList.add("sheet-in"); }
  if (focusTitle) (document.querySelector(".header .title input") as HTMLInputElement | null)?.focus();
  await api.savePad(next).catch((e) => toast(`Could not save: ${e}`));
}

export async function newSheetOn(date: string | null): Promise<void> {
  await flush();
  const tags = state.current?.tags.slice() ?? [];
  await tearTo(newSheet(date, { tags, pinned: date === null }));
}

export const newSheetToday = () => newSheetOn(todayKey());

export async function duplicateSheet(): Promise<void> {
  const cur = state.current;
  if (!cur) return;
  await flush();
  const copy = newSheet(cur.date ?? null, {
    title: `${cur.title || "Untitled sheet"} copy`, tags: cur.tags.slice(), pinned: cur.pinned,
    blocks: cur.blocks.map((b) => ({ ...structuredClone(b), id: uid() })),
    todos: cur.todos.filter((t) => t.status !== "done" && t.text.trim()).map((t) => ({ ...t, id: uid() })),
  });
  await tearTo(copy);
}

export async function deleteSheet(id: string): Promise<void> {
  const pad = state.pads.find((p) => p.id === id) ?? (state.current?.id === id ? state.current : null);
  if (!pad) return;
  const copy = structuredClone(pad);
  await api.deletePad(id).catch((e) => toast(`Could not delete: ${e}`));
  state.pads = state.pads.filter((p) => p.id !== id);
  if (state.current?.id === id) {
    state.current = null;
    const next = state.pads.find((p) => p.date === dayKey()) ?? state.pads[0];
    if (next) { state.current = structuredClone(next); view.all(); } else await openToday();
  } else view.rail();
  toast(`${copy.title || "Untitled sheet"} deleted`, { label: "Undo", run: async () => { await api.savePad(copy); upsert(copy); view.rail(); } });
}

export async function moveSheetTo(date: string): Promise<void> {
  const pad = state.current;
  if (!pad) return;
  pad.date = date;
  pad.pinned = false;
  touch();
  await flush();
  view.all();
}

/** The pad currently shown, for modules that must not hold stale references. */
export const cur = (): Pad => state.current!;
export const sortPref = () => prefs.todoSort;
