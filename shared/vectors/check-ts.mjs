// The Linux TypeScript copies against the vectors, with no packages: Node 22 running the TypeScript directly.
//   node --experimental-transform-types --no-warnings shared/vectors/check-ts.mjs
// Prints how far each copy has drifted from the Swift answers. It reports; it doesn't fail,
// since these copies go once the Linux shell asks the core instead.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const here = path.dirname(new URL(import.meta.url).pathname);
const src = path.join(here, "../../linux/src");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "scratchpad-ts-"));
for (const name of ["formula", "dates", "paste", "markdown", "model"]) {
  const text = fs.readFileSync(path.join(src, `${name}.ts`), "utf8").replace(/from "\.\/(\w+)"/g, 'from "./$1.ts"');
  fs.writeFileSync(path.join(tmp, `${name}.ts`), text);
}
const load = (n) => import(pathToFileURL(path.join(tmp, n)).href);
const [formula, dates, paste, markdown] = await Promise.all(["formula.ts", "dates.ts", "paste.ts", "markdown.ts"].map(load));
const input = JSON.parse(fs.readFileSync(path.join(here, "inputs.json"), "utf8"));
const want = JSON.parse(fs.readFileSync(path.join(here, "expected.json"), "utf8"));

function report(name, got, expected, show = 3) {
  const bad = got.flatMap((g, i) => (JSON.stringify(g) === JSON.stringify(expected[i]) ? [] : [i]));
  console.log(`${name}: ${got.length - bad.length} of ${got.length}`);
  for (const i of bad.slice(0, show)) console.log(`  [${i}] ts ${JSON.stringify(got[i])?.slice(0, 90)}  swift ${JSON.stringify(expected[i])?.slice(0, 90)}`);
}

report("date phrases", input.phrases.map((p) => dates.parsePhrase(p, input.today) ?? null), want.phrases);
report("parseNumber", input.numbers.map((n) => { const v = formula.parseNumber(n); return v === null ? null : v; }), want.numbers.map((n) => (n === null ? null : Number(n))));
report("formatNumber", input.formats.map((f) => formula.formatNumber(f)), want.formats);
const pads = input.sheets.flatMap((s) => { try { return [JSON.parse(s)]; } catch { return []; } }).filter((p) => p && p.id && p.createdAt);
const tables = input.sheets.flatMap((s) => { try { const p = JSON.parse(s); return (p?.blocks ?? []).map((b) => b.rows).filter((r) => Array.isArray(r) && r.flat().every((c) => typeof c === "string")); } catch { return []; } });
report("formula tables", tables.slice(0, want.tables.length).map((t) => formula.evaluate(t).map((r) => r.map(formula.display))), want.tables);
report("paste kinds", input.pastes.map((p) => paste.classify({ plain: p.plain ?? undefined, html: p.html ?? undefined }).map((r) => r.kind)), want.pastes.map((r) => r.map((x) => x.kind)));
fs.rmSync(tmp, { recursive: true });
