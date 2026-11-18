// state.ts against a fake store: saving, duplicating and opening (review 17 Nov, ScratchPad 3, 7, 8, 11).
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Pad } from "../model";

const timers: (() => void)[] = [];
vi.stubGlobal("window", {
  setTimeout: (f: () => void) => { timers.push(f); return timers.length; },
  clearTimeout: () => {},
});
vi.stubGlobal("document", { querySelector: () => null });

const fake = vi.hoisted(() => ({
  pads: [] as Pad[],
  unreadable: [] as string[],
  saved: [] as Pad[],
  failNext: 0,
  todayCalls: 0,
}));
vi.mock("../api", () => ({
  api: {
    listPads: async () => fake.pads.map((p) => structuredClone(p)),
    unreadablePads: async () => fake.unreadable,
    loadPad: async (id: string) => structuredClone(fake.pads.find((p) => p.id === id) ?? null),
    savePad: async (p: Pad) => {
      if (fake.failNext > 0) { fake.failNext--; throw new Error("disk full"); }
      fake.saved.push(structuredClone(p));
      const i = fake.pads.findIndex((x) => x.id === p.id);
      if (i >= 0) fake.pads[i] = structuredClone(p); else fake.pads.push(structuredClone(p));
    },
    todayPad: async () => {
      fake.todayCalls++;
      const { newSheet } = await import("../model");
      const p = newSheet("2026-11-18");
      fake.pads.push(p);
      return structuredClone(p);
    },
    log: () => {},
  },
}));
vi.mock("../ui", () => ({ toast: vi.fn() }));
vi.mock("../motion", () => ({ moving: () => false, after: () => {} }));
vi.mock("../prefs", () => ({ prefs: { newSheetEachDay: false, todoSort: "manual" } }));

const { state, touch, flush, duplicateSheet, openStart } = await import("../state");
const { newSheet } = await import("../model");

beforeEach(() => {
  fake.pads = []; fake.unreadable = []; fake.saved = []; fake.failNext = 0; fake.todayCalls = 0;
  timers.length = 0;
  state.pads = []; state.current = null;
});

describe("state", () => {
  it("keeps an edit unsaved after a failed write, and writes it on the next flush", async () => {
    state.current = newSheet(null, { title: "Ideas" });
    touch();
    fake.failNext = 1;
    await flush();
    expect(fake.saved).toHaveLength(0);
    await flush();
    expect(fake.saved.map((p) => p.id)).toEqual(["ideas"]);
  });

  it("retries a failed write by itself", async () => {
    state.current = newSheet(null, { title: "Ideas" });
    touch();
    fake.failNext = 1;
    await flush();
    timers.at(-1)!();
    await vi.waitFor(() => expect(fake.saved).toHaveLength(1));
  });

  it("duplicating twice makes two sheets, not one written over", async () => {
    const ideas = newSheet(null, { title: "Ideas" });
    fake.pads = [ideas];
    state.pads = [structuredClone(ideas)];
    state.current = structuredClone(ideas);
    await duplicateSheet();
    state.current = structuredClone(ideas);
    await duplicateSheet();
    const ids = fake.saved.map((p) => p.id);
    expect(ids).toEqual(["ideas-copy", "ideas-copy-2"]);
  });

  it("a duplicate doesn't land on a sheet that won't read", async () => {
    const ideas = newSheet(null, { title: "Ideas" });
    fake.pads = [ideas];
    fake.unreadable = ["ideas-copy.json"];
    state.pads = [structuredClone(ideas)];
    state.current = structuredClone(ideas);
    await duplicateSheet();
    expect(fake.saved.map((p) => p.id)).toEqual(["ideas-copy-2"]);
  });

  it("opens the sheet last changed, and makes none, unless New sheet each day is on", async () => {
    fake.pads = [
      newSheet("2026-11-10", { title: "Old", updatedAt: "2026-11-10T09:00:00Z" }),
      newSheet(null, { title: "Ideas", updatedAt: "2026-11-17T21:00:00Z" }),
    ];
    await openStart();
    expect(state.current?.title).toBe("Ideas");
    expect(fake.todayCalls).toBe(0);
  });

  it("makes a first sheet when there are none", async () => {
    await openStart();
    expect(fake.todayCalls).toBe(1);
    expect(state.current?.date).toBe("2026-11-18");
  });
});
