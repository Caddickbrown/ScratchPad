import { describe, expect, it } from "vitest";
import { monthGrid, parsePhrase } from "../dates";

const T = "2026-10-12"; // a Monday
describe("date phrases", () => {
  it("handles words, offsets and weekdays", () => {
    expect(["today", "tomorrow", "yesterday", "+3", "-2", "fri", "Monday", "sun"].map((s) => parsePhrase(s, T)))
      .toEqual(["2026-10-12", "2026-10-13", "2026-10-11", "2026-10-15", "2026-10-10", "2026-10-16", "2026-10-12", "2026-10-18"]);
  });
  it("handles day-month forms and ISO", () => {
    expect(["15 oct", "oct 15", "15/10", "1/2/27", "2026-12-25", "3 January 2027"].map((s) => parsePhrase(s, T)))
      .toEqual(["2026-10-15", "2026-10-15", "2026-10-15", "2027-02-01", "2026-12-25", "2027-01-03"]);
  });
  it("rejects nonsense and impossible dates", () => {
    expect(["", "soon", "31 feb", "2026-13-01", "fr"].map((s) => parsePhrase(s, T))).toEqual([null, null, null, null, null]);
  });
  it("builds a Monday-first month grid", () => {
    const g = monthGrid(2026, 9);
    expect(g[0].slice(0, 4)).toEqual([null, null, null, "2026-10-01"]);
    expect(g.flat().filter(Boolean)).toHaveLength(31);
  });
});
