import { describe, expect, it } from "vitest";
import { cellName, colIndex, colName, display, evaluate, formatNumber, parseNumber } from "../formula";

const show = (rows: string[][]) => evaluate(rows).map((r) => r.map(display));

describe("formulas", () => {
  it("names columns", () => {
    expect([colName(0), colName(25), colName(26), colIndex("AA"), cellName(4, 2)]).toEqual(["A", "Z", "AA", 26, "C5"]);
  });
  it("parses and formats numbers", () => {
    expect([parseNumber("1,240"), parseNumber(" £12 "), parseNumber("15%"), parseNumber("abc"), parseNumber("")]).toEqual([1240, 12, 15, null, null]);
    expect([formatNumber(1110), formatNumber(2 / 3), formatNumber(-1234.5), formatNumber(19)]).toEqual(["1,110", "0.6667", "-1,234.5", "19"]);
  });
  it("evaluates the design's table", () => {
    const rows = [["Item", "Est", "Spent"], ["a", "6", "5"], ["b", "8", "3"], ["c", "5", "0"], ["Total", "=SUM(B2:B4)", "=sum(c2:c4)"]];
    expect(show(rows)[4]).toEqual(["Total", "19", "8"]);
  });
  it("does arithmetic, precedence, unary minus and refs", () => {
    expect(show([["2", "3", "=A1+B1*2", "=(A1+B1)*2", "=-A1+10/4", "=C1-D1"]])[0].slice(2)).toEqual(["8", "10", "0.5", "-2"]);
  });
  it("runs every function and skips text and empty cells", () => {
    const rows = [["1,240", "980", "", "x"], ["=AVG(A1:D1)", "=AVERAGE(A1,B1)", "=MIN(A1:B1)", "=MAX(A1:B1,2000)"], ["=COUNT(A1:D1)", "=SUM(A1:B1, 10)", "=SUM()", ""]];
    expect(show(rows).slice(1)).toEqual([["1,110", "1,110", "980", "2,000"], ["2", "2,230", "0", ""]]);
  });
  it("reports errors", () => {
    const r = show([["=A9", "=1/0", "=C1", "=Z1", "=2+", "=FOO(1)", "=AVG(H1)", ""], ["=D1+1", "1", "", "", "", "", "", ""]]);
    expect(r[0].slice(0, 7)).toEqual(["#REF!", "#DIV/0!", "#CYCLE!", "#REF!", "#ERR!", "#ERR!", "#DIV/0!"]);
    expect(r[1][0]).toBe("#REF!");
  });
  it("propagates errors through references and detects longer cycles", () => {
    expect(show([["=B1", "=A1"], ["=1/0", "=A2*2"]])).toEqual([["#CYCLE!", "#CYCLE!"], ["#DIV/0!", "#DIV/0!"]]);
  });
});
