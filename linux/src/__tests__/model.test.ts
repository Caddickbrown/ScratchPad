import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { carry, dailyPad, isOverdue, matches, moveTodo, nextStatus, padded, rolloverSource, snapBlock, type Pad } from "../model";

describe("model", () => {
  it("snaps to the 24px grid", () => {
    expect(snapBlock({ id: "b", kind: "text", x: 13, y: 35, w: 100 })).toMatchObject({ x: 24, y: 24, w: 96 });
  });
  it("cycles open, done, deferred", () => {
    expect(nextStatus.open).toBe("done");
    expect(nextStatus.done).toBe("deferred");
    expect(nextStatus.deferred).toBe("open");
  });
  it("marks three-day-old open rows overdue", () => {
    const old = { id: "t", text: "x", status: "open" as const, createdAt: new Date(Date.now() - 4 * 86_400_000).toISOString() };
    expect(isOverdue(old)).toBe(true);
    expect(isOverdue({ ...old, status: "done" })).toBe(false);
  });
  it("carries open and deferred rows, not done or empty", () => {
    const prev = dailyPad("2026-10-11");
    prev.todos = [
      { id: "1", text: "a", status: "open", createdAt: "2026-10-11T00:00:00Z" },
      { id: "2", text: "b", status: "done", createdAt: "2026-10-11T00:00:00Z" },
      { id: "3", text: "c", status: "deferred", createdAt: "2026-10-08T00:00:00Z" },
      { id: "4", text: "", status: "open", createdAt: "2026-10-11T00:00:00Z" },
    ];
    const next = carry(prev, dailyPad("2026-10-12"));
    expect(next.todos.map((t) => t.text)).toEqual(["a", "c"]);
    expect(next.todos.every((t) => t.status === "open" && t.carriedFrom === "2026-10-11")).toBe(true);
    expect(next.todos[1].createdAt).toBe("2026-10-08T00:00:00Z");
  });
  it("picks the latest earlier dated pad as rollover source", () => {
    const pads = [dailyPad("2026-10-09"), dailyPad("2026-10-11"), dailyPad("2026-10-13"), { ...dailyPad("x"), id: "ideas", date: null, pinned: true }];
    expect(rolloverSource("2026-10-12", pads)?.id).toBe("2026-10-11");
  });
  it("pads to 18 rows and reads the shared sample", () => {
    const pad = JSON.parse(readFileSync(new URL("../../../shared/samples/2026-10-12.json", import.meta.url), "utf8")) as Pad;
    expect(pad.blocks).toHaveLength(4);
    expect(padded(pad).todos).toHaveLength(18);
  });
  it("searches title, tag, blocks and to-dos", () => {
    const pad = dailyPad("2026-10-12");
    pad.blocks.push({ id: "b", kind: "table", x: 0, y: 0, w: 96, rows: [["Item", "Berlin"]] });
    pad.todos.push({ id: "t", text: "Call Mum", status: "open", createdAt: "2026-10-12T00:00:00Z" });
    expect(matches(pad, "berlin")).toBe(true);
    expect(matches(pad, "MUM")).toBe(true);
    expect(matches(pad, "paris")).toBe(false);
    expect(matches(pad, "")).toBe(true);
  });
  it("moves a to-do before another or to the end", () => {
    const t = (id: string) => ({ id, text: id, status: "open" as const, createdAt: "" });
    const todos = [t("a"), t("b"), t("c")];
    expect(moveTodo(todos, "c", "a").map((x) => x.id)).toEqual(["c", "a", "b"]);
    expect(moveTodo(todos, "a", null).map((x) => x.id)).toEqual(["b", "c", "a"]);
    expect(moveTodo(todos, "b", "b")).toBe(todos);
  });
});
