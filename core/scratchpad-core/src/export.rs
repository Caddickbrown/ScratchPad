//! Markdown and JSON exports.
use crate::dates::long_date;
use crate::formula::TableEvaluator;
use crate::json::encode_pads;
use crate::model::*;
use crate::store::newest_first;
use crate::text::trim_all;

fn newest(sheets: &[Pad]) -> Vec<&Pad> {
    let mut v: Vec<&Pad> = sheets.iter().collect();
    v.sort_by(|a, b| newest_first(a, b));
    v
}

pub fn todo_line(t: &Todo) -> String {
    format!("- [{}] {}{}", if t.status == TodoStatus::Done { "x" } else { " " }, trim_all(&t.text),
            if t.status == TodoStatus::Deferred { " (deferred)" } else { "" })
}

pub fn todos(sheets: &[Pad], include_done: bool, include_deferred: bool, open_only: bool) -> String {
    let mut sections = Vec::new();
    for p in newest(sheets) {
        let rows: Vec<&Todo> = p.todos.iter().filter(|t| t.is_filled()).filter(|t| match t.status {
            TodoStatus::Open => true,
            TodoStatus::Deferred => include_deferred,
            TodoStatus::Done => !open_only && include_done,
        }).collect();
        if rows.is_empty() && (open_only || sheets.len() > 1) { continue; }
        let mut lines = vec![format!("## {}, {}", p.display_title(), long_date(p.date.as_deref())), String::new()];
        lines.extend(rows.iter().map(|t| todo_line(t)));
        sections.push(lines.join("\n"));
    }
    format!("{}\n", sections.join("\n\n"))
}

fn escape_cell(s: &str) -> String { s.replace('|', "\\|").replace('\n', " ") }

pub fn table(rows: &[Vec<String>]) -> String {
    if rows.is_empty() { return String::new(); }
    let mut eval = TableEvaluator::new(rows);
    let cols = eval.column_count.max(1);
    let mut line = |r: usize| -> String {
        let cells: Vec<String> = (0..cols).map(|c| if c < rows[r].len() { escape_cell(&eval.display(r, c)) } else { String::new() }).collect();
        format!("| {} |", cells.join(" | "))
    };
    let mut out = vec![line(0), format!("| {} |", vec!["---"; cols].join(" | "))];
    for r in 1..rows.len() { out.push(line(r)); }
    out.join("\n")
}

pub fn reading_order(blocks: &[Block]) -> Vec<&Block> {
    let mut v: Vec<&Block> = blocks.iter().collect();
    v.sort_by_key(|b| (b.y, b.x));
    v
}

pub fn sheet(p: &Pad) -> String {
    let tag_line = if p.tags.is_empty() { String::new() } else {
        format!(" · {}", p.tags.iter().map(|t| format!("#{}", t)).collect::<Vec<_>>().join(" "))
    };
    let mut out = vec![format!("# {}", p.display_title()), String::new(), format!("_{}{}_", long_date(p.date.as_deref()), tag_line)];
    let s = |v: &Option<String>| v.clone().unwrap_or_default();
    for b in reading_order(&p.blocks) {
        out.push(String::new());
        match b.kind {
            BlockKind::Text => out.push(trim_all(b.text.as_deref().unwrap_or("")).to_string()),
            BlockKind::Code => {
                out.push(format!("```{}", s(&b.language)));
                out.push(s(&b.text));
                out.push("```".into());
            }
            BlockKind::Table => {
                if let Some(c) = b.caption.as_ref().filter(|c| !c.is_empty()) {
                    out.push(format!("**{}**", c));
                    out.push(String::new());
                }
                out.push(table(b.rows.as_deref().unwrap_or(&[])));
            }
            BlockKind::Image => out.push(format!("![{}]({})", s(&b.caption), s(&b.asset))),
            BlockKind::File => out.push(format!("[{}]({})", b.name.as_deref().unwrap_or("file"), s(&b.asset))),
            BlockKind::Link => {
                let text = s(&b.text);
                let title = if text.is_empty() { s(&b.url) } else { text };
                out.push(format!("[{}]({})", title, s(&b.url)));
            }
            BlockKind::Divider => out.push("---".into()),
        }
    }
    let rows: Vec<&Todo> = p.todos.iter().filter(|t| t.is_filled()).collect();
    if !rows.is_empty() {
        out.extend([String::new(), "## To-do".into(), String::new()]);
        out.extend(rows.iter().map(|t| todo_line(t)));
    }
    out.join("\n")
}

pub fn everything(sheets: &[Pad]) -> String {
    let parts: Vec<String> = newest(sheets).into_iter().map(sheet).collect();
    format!("{}\n", parts.join("\n\n---\n\n"))
}

pub fn sheets_json(sheets: &[Pad]) -> Vec<u8> {
    let mut v: Vec<Pad> = sheets.iter().map(Pad::compacted).collect();
    v.sort_by(newest_first);
    encode_pads(&v)
}
