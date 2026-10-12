// Bridge to the Rust store. Falls back to localStorage when running in a plain browser (npm run dev without Tauri).
import type { Pad } from "./model";
import { carry, dailyPad, rolloverSource, todayKey } from "./model";

const tauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<T>(cmd, args);
}

export interface Api {
  listPads(): Promise<Pad[]>;
  loadPad(id: string): Promise<Pad | null>;
  todayPad(): Promise<Pad>;
  savePad(pad: Pad): Promise<void>;
  storeAsset(bytes: ArrayBuffer, ext: string): Promise<string>;
  importFile(path: string): Promise<{ asset: string; name: string; size: number }>;
  assetSrc(rel: string): Promise<string>;
  openExternal(url: string): Promise<void>;
  openPath(rel: string): Promise<void>;
  storeRoot(): Promise<string>;
  fetchTitle(url: string): Promise<string | null>;
}

const tauriApi: Api = {
  listPads: () => invoke("list_pads"),
  loadPad: (id) => invoke("load_pad", { id }),
  todayPad: () => invoke("today_pad"),
  savePad: (pad) => invoke("save_pad", { pad }),
  storeAsset: async (bytes, ext) => invoke("store_asset", { base64Data: toBase64(bytes), ext }),
  importFile: (path) => invoke("import_file", { path }),
  assetSrc: async (rel) => {
    const { convertFileSrc } = await import("@tauri-apps/api/core");
    return convertFileSrc(await invoke<string>("asset_path", { rel }));
  },
  openExternal: async (url) => {
    const { openUrl } = await import("@tauri-apps/plugin-opener");
    await openUrl(url);
  },
  openPath: async (rel) => {
    const { openPath } = await import("@tauri-apps/plugin-opener");
    await openPath(await invoke<string>("asset_path", { rel }));
  },
  storeRoot: () => invoke("store_root"),
  fetchTitle: (url) => invoke("fetch_title", { url }),
};

const KEY = "scratchpad.pads";
const assets = new Map<string, string>();
const browserApi: Api = {
  listPads: async () => {
    const pads = Object.values(JSON.parse(localStorage.getItem(KEY) ?? "{}") as Record<string, Pad>);
    return pads.sort((a, b) => ((a.date ?? "") < (b.date ?? "") ? 1 : -1));
  },
  loadPad: async (id) => (JSON.parse(localStorage.getItem(KEY) ?? "{}") as Record<string, Pad>)[id] ?? null,
  todayPad: async () => {
    const key = todayKey();
    const existing = await browserApi.loadPad(key);
    if (existing) return existing;
    let pad = dailyPad(key);
    const prev = rolloverSource(key, await browserApi.listPads());
    if (prev) pad = carry(prev, pad);
    await browserApi.savePad(pad);
    return pad;
  },
  savePad: async (pad) => {
    const all = JSON.parse(localStorage.getItem(KEY) ?? "{}");
    all[pad.id] = { ...pad, updatedAt: new Date().toISOString() };
    localStorage.setItem(KEY, JSON.stringify(all));
  },
  storeAsset: async (bytes, ext) => {
    const rel = `assets/${crypto.randomUUID()}.${ext}`;
    assets.set(rel, URL.createObjectURL(new Blob([bytes])));
    return rel;
  },
  importFile: async (path) => ({ asset: path, name: path.split("/").pop() ?? "file", size: 0 }),
  assetSrc: async (rel) => assets.get(rel) ?? "",
  openExternal: async (url) => { window.open(url, "_blank"); },
  openPath: async (rel) => { const u = assets.get(rel); if (u) window.open(u, "_blank"); },
  storeRoot: async () => "localStorage (browser preview)",
  fetchTitle: async () => null,
};

export const api: Api = tauri ? tauriApi : browserApi;
export const isTauri = tauri;

function toBase64(buf: ArrayBuffer): string {
  let s = "";
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
