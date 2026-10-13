import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import {
  carry, dayLabel, groupByDay, groupByTag, isOverdue, matches, migrate, moveTodo, newSheet, newSheetId, nextStatus,
  normAngle, normalizeTag, rolloverSources, snapBlock, sortTodos, tagCounts, type Pad, type Todo,
} from "../model";

const sample = (name: string) => JSON.parse(readFileSync(new URL(`../../../shared/samples/${name}`, import.meta.url), "utf8"));
const todo = (id: string, status: Todo["status"] = "open", createdAt = "2026-10-12T00:00:00Z"): Todo => ({ id, text: id, status, createdAt });
const sheet = (date: string | null, o: Partial<Pad> = {}): Pad => newSheet(date, { updatedAt: `${date ?? "2026-01-01"}T10:00:00Z`, ...o });

describe("format", () => {
  it("migrates the v1 sample", () => {
    const p = migrate(sample("pad-v1.json"));
    expect(p.v).toBe(2);
    expect(p.tags).toEqual(["work"]);
    expect("tag" in p).toBe(false);
  });
  it("reads the v2 sample", () => {
    const p = migrate(sample("sheet-v2.json"));
    expect(p.tags).toEqual(["work", "q4"]);
    expect(p.blocks.find((b) => b.font === "hand")?.rotation).toBe(2.5);
  });
  it("makes dated ids and normalises tags and angles", () => {
    expect(newSheetId("2026-10-12")).toMatch(/^2026-10-12-[0-9a-z]{6}$/);
    expect(normalizeTag(" #Q4 Plans!")).toBe("q4plans");
    expect(normAngle(195)).toBe(-165);
    expect(normAngle(-180)).toBe(180);
  });
});

describe("todos", () => {
  it("snaps and cycles", () => {
    expect(snapBlock({ id: "b", kind: "text", x: 13, y: 35, w: 100 })).toMatchObject({ x: 24, y: 24, w: 96 });
    expect([nextStatus.open, nextStatus.done, nextStatus.deferred]).toEqual(["done", "deferred", "open"]);
  });
  it("marks three-day-old open rows overdue", () => {
    expect(isOverdue({ ...todo("x"), createdAt: new Date(Date.now() - 4 * 86_400_000).toISOString() })).toBe(true);
  });
  it("sorts with done sinking in every mode", () => {
    const t = [todo("b", "done"), todo("c"), todo("a", "deferred")];
    expect(sortTodos(t, "manual", true).map((x) => x.id)).toEqual(["c", "a", "b"]);
    expect(sortTodos(t, "manual", false).map((x) => x.id)).toEqual(["b", "c", "a"]);
    expect(sortTodos(t, "az", false).map((x) => x.id)).toEqual(["a", "b", "c"]);
    expect(sortTodos(t, "open", false).map((x) => x.id)).toEqual(["c", "a", "b"]);
    const old = { ...todo("old"), createdAt: "2020-01-01T00:00:00Z" };
    expect(sortTodos([todo("new"), old], "overdue", true)[0].id).toBe("old");
    expect(sortTodos([todo("new"), old], "oldest", true)[0].id).toBe("old");
  });
  it("moves a row before another or to the end", () => {
    const t = [todo("a"), todo("b"), todo("c")];
    expect(moveTodo(t, "c", "a").map((x) => x.id)).toEqual(["c", "a", "b"]);
    expect(moveTodo(t, "a", null).map((x) => x.id)).toEqual(["b", "c", "a"]);
  });
  it("carries open and deferred rows from every sheet of the latest day", () => {
    const a = sheet("2026-10-11", { todos: [todo("a"), todo("b", "done")] });
    const b = sheet("2026-10-11", { todos: [todo("c", "deferred"), todo("")] });
    const old = sheet("2026-10-09", { todos: [todo("old")] });
    const sources = rolloverSources("2026-10-12", [a, b, old, sheet(null, { pinned: true, todos: [todo("pin")] })]);
    expect(sources).toHaveLength(2);
    const next = carry(sources, sheet("2026-10-12"));
    expect(next.todos.map((t) => t.text).sort()).toEqual(["a", "c"]);
    expect(next.todos.every((t) => t.status === "open" && t.carriedFrom)).toBe(true);
  });
});

describe("sidebar", () => {
  const pads = [
    sheet("2026-10-12", { title: "Sprint", tags: ["work", "q4"] }),
    sheet("2026-10-12", { title: "Groceries", tags: ["home"], updatedAt: "2026-10-12T12:00:00Z" }),
    sheet("2026-10-11", { title: "Standup", tags: ["work"] }),
    sheet("2026-10-01", { title: "Old" }),
    sheet(null, { title: "Ideas", pinned: true, tags: ["home"] }),
  ];
  it("labels days", () => {
    expect(dayLabel("2026-10-12", "2026-10-12")).toBe("Today");
    expect(dayLabel("2026-10-11", "2026-10-12")).toBe("Yesterday");
    expect(dayLabel("2026-10-09", "2026-10-12")).toBe("Friday");
    expect(dayLabel("2026-10-01", "2026-10-12")).toBe("Thu 1 Oct");
  });
  it("groups by day, newest first, most recently updated first within a day, pinned excluded", () => {
    const g = groupByDay(pads, "2026-10-12");
    expect(g.map((x) => x.label)).toEqual(["Today", "Yesterday", "Thu 1 Oct"]);
    expect(g[0].sheets.map((s) => s.title)).toEqual(["Groceries", "Sprint"]);
  });
  it("groups by tag with three sorts and untagged last", () => {
    expect(groupByTag(pads, "az").map((g) => g.label)).toEqual(["#home", "#q4", "#work", "Untagged"]);
    expect(groupByTag(pads, "count").map((g) => g.label)).toEqual(["#home", "#work", "#q4", "Untagged"]);
    expect(groupByTag(pads, "recent")[0].label).toBe("#home");
    expect(tagCounts(pads)[0]).toEqual({ tag: "home", count: 2 });
  });
  it("searches tags, cells and to-dos", () => {
    const p = sheet("2026-10-12", { tags: ["q4"], blocks: [{ id: "t", kind: "table", x: 0, y: 0, w: 96, rows: [["Berlin"]] }], todos: [todo("Call Mum")] });
    expect(matches(p, "#q4")).toBe(true);
    expect(matches(p, "berlin")).toBe(true);
    expect(matches(p, "mum")).toBe(true);
    expect(matches(p, "paris")).toBe(false);
  });
});
