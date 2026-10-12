// Mirrors shared/schema/pad.schema.json and the Swift / Rust models. Field names must stay identical.

export const GRID = 24;
export const TODO_ROWS = 18;

export type BlockKind = "text" | "table" | "image" | "file" | "link" | "code" | "divider";
export type TodoStatus = "open" | "done" | "deferred";

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
}

export interface Todo {
  id: string;
  text: string;
  status: TodoStatus;
  createdAt: string;
  carriedFrom?: string | null;
}

export interface Pad {
  v: 1;
  id: string;
  date: string | null;
  title: string;
  tag: string;
  pinned: boolean;
  createdAt: string;
  updatedAt: string;
  blocks: Block[];
  todos: Todo[];
}

export const uid = (): string =>
  (globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36));

export const snap = (v: number): number => Math.round(v / GRID) * GRID;

export function snapBlock(b: Block): Block {
  return { ...b, x: Math.max(0, snap(b.x)), y: Math.max(0, snap(b.y)), w: Math.max(2 * GRID, snap(b.w)) };
}

/** Click order from the design: open, done, deferred, open. */
export const nextStatus: Record<TodoStatus, TodoStatus> = { open: "done", done: "deferred", deferred: "open" };

export const newTodo = (text = ""): Todo => ({ id: uid(), text, status: "open", createdAt: new Date().toISOString(), carriedFrom: null });

/** Open for three or more days counts as overdue. */
export function isOverdue(t: Todo, now = Date.now()): boolean {
  return t.status === "open" && t.text !== "" && now - Date.parse(t.createdAt) >= 3 * 86_400_000;
}

export function todayKey(d = new Date()): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function dailyPad(day: string): Pad {
  const now = new Date().toISOString();
  return { v: 1, id: day, date: day, title: "", tag: "", pinned: false, createdAt: now, updatedAt: now, blocks: [], todos: [] };
}

/** Keeps the column at the paper's 18 rows. Empty rows are display rows until typed in. */
export function padded(pad: Pad): Pad {
  const todos = pad.todos.slice();
  while (todos.length < TODO_ROWS) todos.push(newTodo());
  return { ...pad, todos };
}

/** Midnight rule: open and deferred rows copy over as open, done rows stay. createdAt is kept. */
export function carry(previous: Pad, target: Pad): Pad {
  const carried = previous.todos
    .filter((t) => t.text !== "" && t.status !== "done")
    .map((t) => ({ id: uid(), text: t.text, status: "open" as TodoStatus, createdAt: t.createdAt, carriedFrom: previous.id }));
  return { ...target, todos: [...carried, ...target.todos] };
}

export function rolloverSource(day: string, pads: Pad[]): Pad | undefined {
  return pads
    .filter((p) => !p.pinned && p.date !== null && p.date < day)
    .sort((a, b) => (a.date! < b.date! ? 1 : -1))[0];
}

export const counts = (pad: Pad) => {
  const filled = pad.todos.filter((t) => t.text !== "");
  return {
    total: filled.length,
    done: filled.filter((t) => t.status === "done").length,
    open: filled.filter((t) => t.status === "open").length,
    carried: pad.todos.filter((t) => t.carriedFrom && t.status !== "done" && t.text !== "").length,
  };
};

export function nextFreePoint(pad: Pad): { x: number; y: number } {
  const bottom = pad.blocks.reduce((m, b) => Math.max(m, b.y + (b.h ?? 120)), 0);
  return { x: GRID, y: snap(bottom + GRID) };
}

export function slugify(s: string): string {
  const slug = s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return slug || `pad-${uid().slice(0, 6)}`;
}

/** Case-insensitive search across title, tag, id, block text and to-do text. Mirrors the Rust `matches`. */
export function matches(pad: Pad, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const hit = (s?: string | null) => !!s && s.toLowerCase().includes(q);
  return hit(pad.title) || hit(pad.tag) || hit(pad.id)
    || pad.blocks.some((b) => hit(b.text) || hit(b.name) || hit(b.url) || hit(b.caption) || (b.rows?.some((r) => r.some(hit)) ?? false))
    || pad.todos.some((t) => hit(t.text));
}

/** Moves the to-do with `id` so it sits before `beforeId` (or at the end when null). */
export function moveTodo(todos: Todo[], id: string, beforeId: string | null): Todo[] {
  const moving = todos.find((t) => t.id === id);
  if (!moving || id === beforeId) return todos;
  const rest = todos.filter((t) => t.id !== id);
  const i = beforeId ? rest.findIndex((t) => t.id === beforeId) : -1;
  if (i < 0) return [...rest, moving];
  return [...rest.slice(0, i), moving, ...rest.slice(i)];
}
