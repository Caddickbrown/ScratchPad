// Markdown exports, docs/v0.2-spec.md section 6.
import { evaluate, display } from "./formula";
import { filled, longDate, type Pad, type Todo } from "./model";

export interface TodoMdOptions { includeDone: boolean; includeDeferred: boolean; openOnly?: boolean }

const sheetTitle = (p: Pad) => p.title.trim() || "Untitled sheet";
const newestFirst = (a: Pad, b: Pad) => (b.date ?? "").localeCompare(a.date ?? "") || b.updatedAt.localeCompare(a.updatedAt);

export function todoLine(t: Todo): string {
  return `- [${t.status === "done" ? "x" : " "}] ${t.text.trim()}${t.status === "deferred" ? " (deferred)" : ""}`;
}

export function todosMarkdown(sheets: Pad[], o: TodoMdOptions): string {
  const sections: string[] = [];
  for (const p of sheets.slice().sort(newestFirst)) {
    const rows = p.todos.filter(filled).filter((t) =>
      o.openOnly ? t.status === "open" || (t.status === "deferred" && o.includeDeferred)
        : t.status === "open" || (t.status === "done" && o.includeDone) || (t.status === "deferred" && o.includeDeferred));
    if (!rows.length && (o.openOnly || sheets.length > 1)) continue;
    sections.push([`## ${sheetTitle(p)}, ${longDate(p.date)}`, "", ...rows.map(todoLine)].join("\n"));
  }
  return sections.join("\n\n") + "\n";
}

const esc = (s: string) => s.replace(/\|/g, "\\|").replace(/\n/g, " ");

export function tableMarkdown(rows: string[][]): string {
  if (!rows.length) return "";
  const vals = evaluate(rows).map((r) => r.map(display));
  const cols = Math.max(...vals.map((r) => r.length));
  const line = (r: string[]) => `| ${Array.from({ length: cols }, (_, i) => esc(r[i] ?? "")).join(" | ")} |`;
  return [line(vals[0]), `| ${Array(cols).fill("---").join(" | ")} |`, ...vals.slice(1).map(line)].join("\n");
}

export function sheetMarkdown(p: Pad): string {
  const out: string[] = [`# ${sheetTitle(p)}`, "", `_${longDate(p.date)}${p.tags.length ? ` · ${p.tags.map((t) => `#${t}`).join(" ")}` : ""}_`];
  for (const b of p.blocks.slice().sort((a, b) => a.y - b.y || a.x - b.x)) {
    out.push("");
    switch (b.kind) {
      case "text": out.push((b.text ?? "").trim()); break;
      case "code": out.push("```" + (b.language ?? ""), b.text ?? "", "```"); break;
      case "table": out.push(...(b.caption ? [`**${b.caption}**`, ""] : []), tableMarkdown(b.rows ?? [])); break;
      case "image": out.push(`![${b.caption ?? ""}](${b.asset ?? ""})`); break;
      case "file": out.push(`[${b.name ?? "file"}](${b.asset ?? ""})`); break;
      case "link": out.push(`[${b.text || b.url}](${b.url ?? ""})`); break;
      case "divider": out.push("---"); break;
    }
  }
  const todos = p.todos.filter(filled);
  if (todos.length) out.push("", "## To-do", "", ...todos.map(todoLine));
  return out.join("\n");
}

export function everythingMarkdown(sheets: Pad[]): string {
  return sheets.slice().sort(newestFirst).map(sheetMarkdown).join("\n\n---\n\n") + "\n";
}
