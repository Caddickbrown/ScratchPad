// Table formulas, docs/v0.2-spec.md section 4. Pure; shared semantics with the Swift evaluator.

export type CellValue = { kind: "num"; value: number } | { kind: "text"; value: string } | { kind: "empty" } | { kind: "error"; code: FormulaError };
export type FormulaError = "#REF!" | "#DIV/0!" | "#CYCLE!" | "#ERR!";

class FErr extends Error { constructor(public code: FormulaError) { super(code); } }

export function colName(i: number): string {
  let s = "";
  for (let n = i + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s;
  return s;
}
export function colIndex(name: string): number {
  let n = 0;
  for (const ch of name.toUpperCase()) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}
export const cellName = (r: number, c: number) => `${colName(c)}${r + 1}`;

/** "1,240", " £12 ", "15%" -> number; anything else -> null. */
export function parseNumber(raw: string): number | null {
  const s = raw.trim().replace(/^[£$€]/, "").replace(/%$/, "").replace(/,/g, "").trim();
  if (!s || !/^[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/i.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

export function formatNumber(n: number): string {
  const rounded = Math.round(n * 1e4) / 1e4;
  const [int, frac] = Math.abs(rounded).toFixed(4).replace(/\.?0+$/, "").split(".");
  const grouped = Math.abs(rounded) >= 1000 ? int.replace(/\B(?=(\d{3})+(?!\d))/g, ",") : int;
  return (rounded < 0 ? "-" : "") + grouped + (frac ? `.${frac}` : "");
}

type Tok = { t: "num"; v: number } | { t: "ref"; r: number; c: number } | { t: "id"; v: string } | { t: "op"; v: string };

function tokenize(src: string): Tok[] {
  const out: Tok[] = [];
  let i = 0;
  while (i < src.length) {
    const ch = src[i];
    if (/\s/.test(ch)) { i++; continue; }
    if (/[0-9.]/.test(ch)) {
      const m = /^(\d+\.?\d*|\.\d+)(e[-+]?\d+)?/i.exec(src.slice(i));
      if (!m) throw new FErr("#ERR!");
      out.push({ t: "num", v: Number(m[0]) }); i += m[0].length; continue;
    }
    if (/[A-Za-z]/.test(ch)) {
      const m = /^[A-Za-z]+\d*/.exec(src.slice(i))!;
      const ref = /^([A-Za-z]{1,3})(\d+)$/.exec(m[0]);
      if (ref) out.push({ t: "ref", r: Number(ref[2]) - 1, c: colIndex(ref[1]) });
      else out.push({ t: "id", v: m[0].toUpperCase() });
      i += m[0].length; continue;
    }
    if ("+-*/(),:".includes(ch)) { out.push({ t: "op", v: ch }); i++; continue; }
    throw new FErr("#ERR!");
  }
  return out;
}

const FUNCS = new Set(["SUM", "AVG", "AVERAGE", "MIN", "MAX", "COUNT"]);

/** Evaluates every cell of a table. Raw cells that do not start with = are text or numbers. */
export function evaluate(rows: string[][]): CellValue[][] {
  const memo = new Map<string, CellValue>();
  const visiting = new Set<string>();

  const cell = (r: number, c: number): CellValue => {
    if (r < 0 || c < 0 || r >= rows.length || c >= (rows[r]?.length ?? 0)) throw new FErr("#REF!");
    const key = `${r},${c}`;
    if (memo.has(key)) return memo.get(key)!;
    if (visiting.has(key)) throw new FErr("#CYCLE!");
    const raw = rows[r][c] ?? "";
    let v: CellValue;
    if (raw.trim().startsWith("=")) {
      visiting.add(key);
      try { v = { kind: "num", value: formula(raw.trim().slice(1)) }; }
      catch (e) { v = { kind: "error", code: e instanceof FErr ? e.code : "#ERR!" }; }
      visiting.delete(key);
    } else if (raw.trim() === "") v = { kind: "empty" };
    else { const n = parseNumber(raw); v = n === null ? { kind: "text", value: raw } : { kind: "num", value: n }; }
    memo.set(key, v);
    return v;
  };

  const numOf = (v: CellValue): number => {
    if (v.kind === "error") throw new FErr(v.code);
    return v.kind === "num" ? v.value : 0;
  };

  const formula = (src: string): number => {
    const toks = tokenize(src);
    let p = 0;
    const peek = () => toks[p];
    const eat = (v: string) => { const t = toks[p]; if (t?.t === "op" && t.v === v) { p++; return true; } return false; };

    // Function args flatten to the cell values they cover; scalar args are numbers.
    const arg = (): CellValue[] => {
      const t = peek();
      if (t?.t === "ref" && toks[p + 1]?.t === "op" && (toks[p + 1] as any).v === ":") {
        const end = toks[p + 2];
        if (end?.t !== "ref") throw new FErr("#ERR!");
        p += 3;
        const out: CellValue[] = [];
        for (let r = Math.min(t.r, end.r); r <= Math.max(t.r, end.r); r++)
          for (let c = Math.min(t.c, end.c); c <= Math.max(t.c, end.c); c++) out.push(cell(r, c));
        return out;
      }
      if (t?.t === "ref" && !isOperatorNext()) { p++; return [cell(t.r, t.c)]; }
      return [{ kind: "num", value: expr() }];
    };
    const isOperatorNext = () => { const n = toks[p + 1]; return n?.t === "op" && "+-*/".includes(n.v); };

    const call = (name: string): number => {
      if (!eat("(")) throw new FErr("#ERR!");
      const vals: CellValue[] = [];
      if (!eat(")")) {
        do vals.push(...arg()); while (eat(","));
        if (!eat(")")) throw new FErr("#ERR!");
      }
      for (const v of vals) if (v.kind === "error") throw new FErr(v.code);
      const nums = vals.filter((v): v is { kind: "num"; value: number } => v.kind === "num").map((v) => v.value);
      switch (name) {
        case "SUM": return nums.reduce((a, b) => a + b, 0);
        case "AVG": case "AVERAGE": if (!nums.length) throw new FErr("#DIV/0!"); return nums.reduce((a, b) => a + b, 0) / nums.length;
        case "MIN": return nums.length ? Math.min(...nums) : 0;
        case "MAX": return nums.length ? Math.max(...nums) : 0;
        case "COUNT": return nums.length;
      }
      throw new FErr("#ERR!");
    };

    const atom = (): number => {
      const t = peek();
      if (!t) throw new FErr("#ERR!");
      if (t.t === "op" && t.v === "-") { p++; return -atom(); }
      if (t.t === "op" && t.v === "+") { p++; return atom(); }
      if (t.t === "op" && t.v === "(") { p++; const v = expr(); if (!eat(")")) throw new FErr("#ERR!"); return v; }
      if (t.t === "num") { p++; return t.v; }
      if (t.t === "ref") { p++; return numOf(cell(t.r, t.c)); }
      if (t.t === "id" && FUNCS.has(t.v)) { p++; return call(t.v); }
      throw new FErr("#ERR!");
    };
    const term = (): number => {
      let v = atom();
      for (;;) {
        if (eat("*")) v *= atom();
        else if (eat("/")) { const d = atom(); if (d === 0) throw new FErr("#DIV/0!"); v /= d; }
        else return v;
      }
    };
    function expr(): number {
      let v = term();
      for (;;) {
        if (eat("+")) v += term();
        else if (eat("-")) v -= term();
        else return v;
      }
    }

    const v = expr();
    if (p !== toks.length) throw new FErr("#ERR!");
    if (!Number.isFinite(v)) throw new FErr("#ERR!");
    return v;
  };

  return rows.map((row, r) => row.map((_, c) => cell(r, c)));
}

export function display(v: CellValue): string {
  switch (v.kind) {
    case "num": return formatNumber(v.value);
    case "text": return v.value;
    case "empty": return "";
    case "error": return v.code;
  }
}

export const isFormula = (raw: string) => raw.trim().startsWith("=");
