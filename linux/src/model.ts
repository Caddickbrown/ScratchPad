// Mirrors shared/schema/pad.schema.json (v2) and the Swift / Rust models. Field names must stay identical.
// UI copy says "sheet"; the type stays Pad for continuity with the file format.

export const GRID = 24;

export type BlockKind = "text" | "table" | "image" | "file" | "link" | "code" | "divider";
export type TodoStatus = "open" | "done" | "deferred";
export type FontFamily = "sans" | "serif" | "mono" | "hand";

export interface Block {
  id: string;
  kind: BlockKind;
  x: number;
  y: number;
  w: number;
  h?: number | null;
  text?: string;
  rows?: string[][];
  asset?: string;
  name?: string;
  size?: number;
  url?: string;
  caption?: string;
  language?: string;
  rotation?: number;
  font?: FontFamily;
  fontSize?: number;
  bold?: boolean;
  italic?: boolean;
  colWidths?: number[];
}

export interface Todo {
  id: string;
  text: string;
  status: TodoStatus;
  createdAt: string;
  carriedFrom?: string | null;
}

export interface Pad {
  v: 2;
  id: string;
  date: string | null;
  title: string;
  tags: string[];
  pinned: boolean;
  createdAt: string;
  updatedAt: string;
  blocks: Block[];
  todos: Todo[];
}

export const uid = (): string =>
  globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36);

export const snap = (v: number): number => Math.round(v / GRID) * GRID;

export function snapBlock(b: Block): Block {
  return { ...b, x: Math.max(0, snap(b.x)), y: Math.max(0, snap(b.y)), w: Math.max(2 * GRID, snap(b.w)) };
}

/** Degrees normalised to (-180, 180]. */
export function normAngle(a: number): number {
  let r = ((a % 360) + 360) % 360;
  if (r > 180) r -= 360;
  return Math.round(r * 10) / 10;
}

export const nextStatus: Record<TodoStatus, TodoStatus> = { open: "done", done: "deferred", deferred: "open" };

export const newTodo = (text = ""): Todo => ({ id: uid(), text, status: "open", createdAt: new Date().toISOString(), carriedFrom: null });

export const filled = (t: Todo) => t.text.trim() !== "";

/** Open for three or more days counts as overdue. */
export function isOverdue(t: Todo, now = Date.now()): boolean {
  return t.status === "open" && filled(t) && now - Date.parse(t.createdAt) >= 3 * 86_400_000;
}

export function dayKey(d = new Date()): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
export const todayKey = () => dayKey();

export function parseDay(key: string): Date {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d);
}

/** `YYYY-MM-DD-xxxxxx`. */
export function newSheetId(day: string): string {
  const a = "0123456789abcdefghijklmnopqrstuvwxyz";
  let s = "";
  const bytes = new Uint8Array(6);
  (globalThis.crypto ?? { getRandomValues: (b: Uint8Array) => b.map(() => Math.floor(Math.random() * 256)) }).getRandomValues(bytes);
  for (const b of bytes) s += a[b % 36];
  return `${day}-${s}`;
}

export function slugify(s: string): string {
  const slug = s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60);
  return slug || `sheet-${uid().slice(0, 6)}`;
}

export function normalizeTag(t: string): string {
  return t.trim().replace(/^#+/, "").toLowerCase().replace(/[^a-z0-9_-]/g, "");
}

export function newSheet(date: string | null, opts: Partial<Pad> = {}): Pad {
  const now = new Date().toISOString();
  return {
    v: 2, id: date ? newSheetId(date) : slugify(opts.title ?? ""), date, title: "", tags: [], pinned: date === null,
    createdAt: now, updatedAt: now, blocks: [], todos: [], ...opts,
  };
}

/** Accepts v1 (single `tag`) and v2, returns v2. */
export function migrate(raw: any): Pad {
  const tags: string[] = [];
  const add = (t: unknown) => { const n = typeof t === "string" ? normalizeTag(t) : ""; if (n && !tags.includes(n)) tags.push(n); };
  if (typeof raw.tag === "string") add(raw.tag);
  if (Array.isArray(raw.tags)) raw.tags.forEach(add);
  const { tag: _drop, ...rest } = raw;
  // v0.1 padded the column with 18 empty rows; v0.2 shows one blank row instead, so empties are dropped.
  const todos = (raw.todos ?? []).filter((t: Todo) => typeof t.text === "string" && t.text.trim() !== "");
  return { ...rest, v: 2, tags, title: raw.title ?? "", pinned: !!raw.pinned, blocks: raw.blocks ?? [], todos, date: raw.date ?? null } as Pad;
}

/** Midnight rule across sheets: open and deferred rows copy over as open, done rows stay, createdAt kept. */
export function carry(sources: Pad[], target: Pad): Pad {
  const carried = sources.flatMap((p) => p.todos.filter((t) => filled(t) && t.status !== "done")
    .map((t) => ({ id: uid(), text: t.text, status: "open" as TodoStatus, createdAt: t.createdAt, carriedFrom: p.id })));
  return { ...target, todos: [...carried, ...target.todos] };
}

/** Every unpinned sheet of the latest date strictly before `day`. */
export function rolloverSources(day: string, pads: Pad[]): Pad[] {
  const dates = pads.filter((p) => !p.pinned && p.date && p.date < day).map((p) => p.date!);
  if (!dates.length) return [];
  const latest = dates.sort().at(-1);
  return pads.filter((p) => !p.pinned && p.date === latest);
}

export const counts = (pad: Pad) => {
  const f = pad.todos.filter(filled);
  return {
    total: f.length,
    done: f.filter((t) => t.status === "done").length,
    open: f.filter((t) => t.status === "open").length,
    carried: f.filter((t) => t.carriedFrom && t.status !== "done").length,
  };
};

export function nextFreePoint(pad: Pad): { x: number; y: number } {
  const bottom = pad.blocks.reduce((m, b) => Math.max(m, b.y + (b.h ?? 120)), 0);
  return { x: GRID, y: snap(bottom + GRID) };
}

/** Search across title, tags, id, block text, cells, names, urls, captions and to-dos. */
export function matches(pad: Pad, query: string): boolean {
  const q = query.trim().toLowerCase().replace(/^#/, "");
  if (!q) return true;
  const hit = (s?: string | null) => !!s && s.toLowerCase().includes(q);
  return hit(pad.title) || pad.tags.some(hit) || hit(pad.id)
    || pad.blocks.some((b) => hit(b.text) || hit(b.name) || hit(b.url) || hit(b.caption) || (b.rows?.some((r) => r.some(hit)) ?? false))
    || pad.todos.some((t) => hit(t.text));
}

// ---------- to-do ordering ----------

export type SortMode = "manual" | "open" | "overdue" | "az" | "oldest";
const rank: Record<TodoStatus, number> = { open: 0, deferred: 1, done: 2 };

/** View order for the column. Stable; `sink` pushes done rows to the bottom in every mode. */
export function sortTodos(todos: Todo[], mode: SortMode, sink: boolean, now = Date.now()): Todo[] {
  const idx = new Map(todos.map((t, i) => [t.id, i]));
  const by = (f: (a: Todo, b: Todo) => number) => (a: Todo, b: Todo) => f(a, b) || idx.get(a.id)! - idx.get(b.id)!;
  const sinkCmp = (a: Todo, b: Todo) => (sink ? Number(a.status === "done") - Number(b.status === "done") : 0);
  const cmp: Record<SortMode, (a: Todo, b: Todo) => number> = {
    manual: () => 0,
    open: (a, b) => rank[a.status] - rank[b.status],
    overdue: (a, b) => Number(isOverdue(b, now)) - Number(isOverdue(a, now)) || rank[a.status] - rank[b.status],
    az: (a, b) => a.text.localeCompare(b.text, undefined, { sensitivity: "base" }),
    oldest: (a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt),
  };
  return todos.slice().sort(by((a, b) => sinkCmp(a, b) || cmp[mode](a, b)));
}

/** Moves the to-do with `id` so it sits before `beforeId` (or at the end when null). */
export function moveTodo(todos: Todo[], id: string, beforeId: string | null): Todo[] {
  const moving = todos.find((t) => t.id === id);
  if (!moving || id === beforeId) return todos;
  const rest = todos.filter((t) => t.id !== id);
  const i = beforeId ? rest.findIndex((t) => t.id === beforeId) : -1;
  return i < 0 ? [...rest, moving] : [...rest.slice(0, i), moving, ...rest.slice(i)];
}

// ---------- sidebar grouping ----------

const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export function shortDate(key: string): string { const d = parseDay(key); return `${d.getDate()} ${MONTHS[d.getMonth()]}`; }
export function longDate(key: string | null): string {
  if (!key) return "Pinned";
  const d = parseDay(key);
  return `${DAYS[d.getDay()].slice(0, 3)} ${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** Today, Yesterday, weekday within 6 days, else `ddd d MMM`. */
export function dayLabel(key: string, today = todayKey()): string {
  const diff = Math.round((parseDay(today).getTime() - parseDay(key).getTime()) / 86_400_000);
  if (diff === 0) return "Today";
  if (diff === 1) return "Yesterday";
  if (diff === -1) return "Tomorrow";
  const d = parseDay(key);
  if (diff > 1 && diff <= 6) return DAYS[d.getDay()];
  return `${DAYS[d.getDay()].slice(0, 3)} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

export interface Group { key: string; label: string; meta: string; sheets: Pad[] }
export type TagSort = "az" | "count" | "recent";

/** Dated sheets by day, newest first; pinned sheets are excluded (they have their own section). */
export function groupByDay(pads: Pad[], today = todayKey()): Group[] {
  const groups = new Map<string, Group>();
  for (const p of pads.filter((p) => !p.pinned && p.date).sort((a, b) => (b.date! > a.date! ? 1 : b.date! < a.date! ? -1 : b.updatedAt.localeCompare(a.updatedAt)))) {
    if (!groups.has(p.date!)) groups.set(p.date!, { key: p.date!, label: dayLabel(p.date!, today), meta: shortDate(p.date!), sheets: [] });
    groups.get(p.date!)!.sheets.push(p);
  }
  return [...groups.values()];
}

/** One group per tag (a sheet appears under each of its tags), Untagged last. Pinned sheets included. */
export function groupByTag(pads: Pad[], sort: TagSort): Group[] {
  const groups = new Map<string, Group & { recent: string }>();
  for (const p of pads) {
    for (const t of p.tags.length ? p.tags : [""]) {
      if (!groups.has(t)) groups.set(t, { key: t, label: t ? `#${t}` : "Untagged", meta: "", sheets: [], recent: "" });
      const g = groups.get(t)!;
      g.sheets.push(p);
      if (p.updatedAt > g.recent) g.recent = p.updatedAt;
    }
  }
  const list = [...groups.values()];
  list.forEach((g) => {
    g.meta = String(g.sheets.length);
    g.sheets.sort((a, b) => (b.date ?? "") .localeCompare(a.date ?? "") || b.updatedAt.localeCompare(a.updatedAt));
  });
  list.sort((a, b) => {
    if (!a.key) return 1;
    if (!b.key) return -1;
    if (sort === "count") return b.sheets.length - a.sheets.length || a.key.localeCompare(b.key);
    if (sort === "recent") return b.recent.localeCompare(a.recent) || a.key.localeCompare(b.key);
    return a.key.localeCompare(b.key);
  });
  return list.map(({ recent: _r, ...g }) => g);
}

/** Tags in use with sheet counts, most used first. */
export function tagCounts(pads: Pad[]): { tag: string; count: number }[] {
  const m = new Map<string, number>();
  pads.forEach((p) => p.tags.forEach((t) => m.set(t, (m.get(t) ?? 0) + 1)));
  return [...m.entries()].map(([tag, count]) => ({ tag, count })).sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag));
}
