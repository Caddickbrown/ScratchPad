// Bridge to the Rust store. Falls back to localStorage in a plain browser (npm run dev without Tauri).
import { carry, dayKey, migrate, newSheet, rolloverSources, type Pad } from "./model";

const tauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
export const isTauri = tauri;

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<T>(cmd, args);
}

export interface FileFilter { name: string; extensions: string[] }

export interface Api {
  listPads(): Promise<Pad[]>;
  loadPad(id: string): Promise<Pad | null>;
  todayPad(): Promise<Pad>;
  savePad(pad: Pad): Promise<void>;
  deletePad(id: string): Promise<void>;
  storeAsset(bytes: ArrayBuffer, ext: string): Promise<string>;
  importFile(path: string): Promise<{ asset: string; name: string; size: number }>;
  assetSrc(rel: string): Promise<string>;
  openExternal(url: string): Promise<void>;
  openPath(rel: string): Promise<void>;
  storeRoot(): Promise<string>;
  fetchTitle(url: string): Promise<string | null>;
  archiveJson(tag?: string): Promise<string>;
  importArchiveJson(json: string): Promise<{ sheets: number; assets: number }>;
  /** Asks where to save, then writes. Resolves false when the user cancels. */
  saveFile(defaultName: string, data: string | Uint8Array, filter: FileFilter): Promise<boolean>;
  /** Asks for a file and returns its text, or null when cancelled. */
  openTextFile(filter: FileFilter): Promise<string | null>;
  log(msg: string): void;
}

const tauriApi: Api = {
  listPads: async () => (await invoke<Pad[]>("list_pads")).map(migrate),
  loadPad: async (id) => { const p = await invoke<Pad | null>("load_pad", { id }); return p ? migrate(p) : null; },
  todayPad: async () => migrate(await invoke<Pad>("today_pad")),
  savePad: (pad) => invoke("save_pad", { pad }),
  deletePad: (id) => invoke("delete_pad", { id }),
  storeAsset: async (bytes, ext) => invoke("store_asset", { base64Data: toBase64(bytes), ext }),
  importFile: (path) => invoke("import_file", { path }),
  assetSrc: async (rel) => {
    const { convertFileSrc } = await import("@tauri-apps/api/core");
    return convertFileSrc(await invoke<string>("asset_path", { rel }));
  },
  openExternal: async (url) => { const { openUrl } = await import("@tauri-apps/plugin-opener"); await openUrl(url); },
  openPath: async (rel) => { const { openPath } = await import("@tauri-apps/plugin-opener"); await openPath(await invoke<string>("asset_path", { rel })); },
  storeRoot: () => invoke("store_root"),
  fetchTitle: (url) => invoke("fetch_title", { url }),
  archiveJson: (tag) => invoke("archive_json", { tag: tag ?? null }),
  importArchiveJson: (json) => invoke("import_archive_json", { json }),
  saveFile: async (defaultName, data, filter) => {
    const { save } = await import("@tauri-apps/plugin-dialog");
    const path = await save({ defaultPath: defaultName, filters: [filter] });
    if (!path) return false;
    const fs = await import("@tauri-apps/plugin-fs");
    if (typeof data === "string") await fs.writeTextFile(path, data);
    else await fs.writeFile(path, data);
    return true;
  },
  openTextFile: async (filter) => {
    const { open } = await import("@tauri-apps/plugin-dialog");
    const path = await open({ multiple: false, directory: false, filters: [filter] });
    if (!path || Array.isArray(path)) return null;
    const { readTextFile } = await import("@tauri-apps/plugin-fs");
    return readTextFile(path);
  },
  log: (msg) => { invoke("debug_log", { msg }).catch(() => {}); },
};

// ---------- browser preview ----------

const KEY = "scratchpad.pads.v2";
const assets = new Map<string, string>();
const readAll = (): Record<string, Pad> => {
  try {
    const all = JSON.parse(localStorage.getItem(KEY) ?? "{}");
    for (const k of Object.keys(all)) all[k] = migrate(all[k]);
    return all;
  } catch { return {}; }
};
const writeAll = (all: Record<string, Pad>) => { try { localStorage.setItem(KEY, JSON.stringify(all)); } catch { /* private window */ } };

const browserApi: Api = {
  listPads: async () => Object.values(readAll()).sort((a, b) => (b.date ?? "").localeCompare(a.date ?? "") || b.updatedAt.localeCompare(a.updatedAt)),
  loadPad: async (id) => readAll()[id] ?? null,
  todayPad: async () => {
    const key = dayKey();
    const pads = await browserApi.listPads();
    const existing = pads.filter((p) => p.date === key).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))[0];
    if (existing) return existing;
    const pad = carry(rolloverSources(key, pads), newSheet(key));
    await browserApi.savePad(pad);
    return pad;
  },
  savePad: async (pad) => { const all = readAll(); all[pad.id] = { ...pad, v: 2, updatedAt: new Date().toISOString() }; writeAll(all); },
  deletePad: async (id) => { const all = readAll(); delete all[id]; writeAll(all); },
  storeAsset: async (bytes, ext) => {
    const rel = `assets/${crypto.randomUUID()}.${ext}`;
    assets.set(rel, URL.createObjectURL(new Blob([bytes])));
    return rel;
  },
  importFile: async (path) => ({ asset: path, name: path.split("/").pop() ?? "file", size: 0 }),
  assetSrc: async (rel) => assets.get(rel) ?? "",
  openExternal: async (url) => { window.open(url, "_blank"); },
  openPath: async (rel) => { const u = assets.get(rel); if (u) window.open(u, "_blank"); },
  storeRoot: async () => "Browser preview (localStorage)",
  fetchTitle: async () => null,
  archiveJson: async (tag) => JSON.stringify({ format: "scratchpad-archive", v: 1, exportedAt: new Date().toISOString(),
    sheets: (await browserApi.listPads()).filter((p) => !tag || p.tags.includes(tag)), assets: {} }),
  importArchiveJson: async (json) => {
    const a = JSON.parse(json);
    if (a?.format !== "scratchpad-archive" || !Array.isArray(a.sheets)) throw new Error("That file is not a Scratchpad archive");
    const all = readAll();
    for (const s of a.sheets) all[s.id] = migrate(s);
    writeAll(all);
    return { sheets: a.sheets.length, assets: 0 };
  },
  saveFile: async (defaultName, data, _filter) => {
    const blob = new Blob([data as BlobPart]);
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = defaultName;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    return true;
  },
  openTextFile: () => new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.onchange = async () => resolve(input.files?.[0] ? await input.files[0].text() : null);
    input.click();
  }),
  log: (msg) => console.log(msg),
};

export const api: Api = tauri ? tauriApi : browserApi;

function toBase64(buf: ArrayBuffer): string {
  let s = "";
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
