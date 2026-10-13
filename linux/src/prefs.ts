// Per-device view preferences. Never part of the sheet file.
import type { FontFamily, SortMode, TagSort } from "./model";

export type Appearance = "system" | "light" | "dark";
export type Whimsy = "full" | "subtle" | "off";

export interface Prefs {
  appearance: Appearance;
  whimsy: Whimsy;
  groupBy: "day" | "tag";
  tagSort: TagSort;
  todoSort: SortMode;
  sink: boolean;
  defaultFont: FontFamily;
  railOpen: boolean;
}

const KEY = "scratchpad.prefs";
const defaults: Prefs = { appearance: "system", whimsy: "full", groupBy: "day", tagSort: "az", todoSort: "manual", sink: true, defaultFont: "sans", railOpen: true };

function load(): Prefs {
  try { return { ...defaults, ...JSON.parse(localStorage.getItem(KEY) ?? "{}") }; } catch { return { ...defaults }; }
}

export const prefs: Prefs = load();

export function setPref<K extends keyof Prefs>(key: K, value: Prefs[K]): void {
  prefs[key] = value;
  try { localStorage.setItem(KEY, JSON.stringify(prefs)); } catch { /* private window */ }
}

/** Shown-once flags, e.g. the all-clear stamp per sheet per day. */
export function once(key: string): boolean {
  const k = `scratchpad.once.${key}`;
  try {
    if (localStorage.getItem(k)) return false;
    localStorage.setItem(k, "1");
  } catch { /* private window: show every time */ }
  return true;
}
