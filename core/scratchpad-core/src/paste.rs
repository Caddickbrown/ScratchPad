//! PasteClassifier, TableParser, Placement and LinkTitle.parse.
use crate::model::*;
use crate::text::{graphemes, split_lf, trim_all, trim_nl, trim_ws};
use regex::Regex;
use std::sync::OnceLock;

#[derive(Clone, Default)]
pub struct ClipboardContents {
    pub plain: Option<String>,
    pub html: Option<String>,
    pub file_paths: Vec<String>,
    pub image: Option<Vec<u8>>,
    pub image_ext: String,
}

#[derive(Clone, PartialEq, Debug)]
pub enum PasteResult {
    Text(String),
    Code(String, Option<String>),
    Link(String, Option<String>),
    Table(Vec<Vec<String>>),
    Image(Vec<u8>, String),
    File(String),
}

struct Patterns { table: Regex, tr: Regex, cell: Regex, tag: Regex, title: Regex }

fn patterns() -> &'static Patterns {
    static P: OnceLock<Patterns> = OnceLock::new();
    P.get_or_init(|| Patterns {
        table: Regex::new(r"(?is)<table\b.*?</table>").unwrap(),
        tr: Regex::new(r"(?is)<tr\b.*?</tr>").unwrap(),
        cell: Regex::new(r"(?is)<t[dh]\b[^>]*>(.*?)</t[dh]>").unwrap(),
        tag: Regex::new(r"<[^>]+>").unwrap(),
        title: Regex::new(r"(?is)<title\b[^>]*>(.*?)</title>").unwrap(),
    })
}

pub fn decode_entities(s: &str) -> String {
    if !s.contains('&') { return s.to_string(); }
    s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'")
}

pub fn rows_from_tsv(s: &str) -> Option<Vec<Vec<String>>> {
    let lines = split_lf(s);
    if lines.len() < 2 || !lines.iter().all(|l| l.contains('\t')) { return None; }
    let rows: Vec<Vec<String>> = lines.iter().map(|l| l.split('\t').map(|c| trim_ws(c).to_string()).collect()).collect();
    let cols = rows[0].len();
    if cols < 2 || !rows.iter().all(|r| r.len() == cols) { return None; }
    Some(rows)
}

pub fn rows_from_html(html: &str) -> Option<Vec<Vec<String>>> {
    let p = patterns();
    let table = p.table.find(html)?.as_str();
    let mut rows: Vec<Vec<String>> = Vec::new();
    for tr in p.tr.find_iter(table) {
        let cells: Vec<String> = p.cell.captures_iter(tr.as_str()).map(|c| {
            let stripped = p.tag.replace_all(&c[1], "");
            trim_all(&decode_entities(&stripped)).to_string()
        }).collect();
        if !cells.is_empty() { rows.push(cells); }
    }
    if rows.is_empty() { return None; }
    let cols = rows.iter().map(|r| r.len()).max().unwrap_or(0);
    for r in &mut rows { r.resize(cols, String::new()); }
    Some(rows)
}

/// `URL(string:)` with an http(s) scheme and a host.
fn single_url(s: &str) -> Option<String> {
    if s.contains('\n') || s.contains(' ') { return None; }
    let (scheme, rest) = s.split_once(':')?;
    let lower = scheme.to_ascii_lowercase();
    if lower != "http" && lower != "https" { return None; }
    let rest = rest.strip_prefix("//")?;
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    if authority.is_empty() { return None; }
    let host = authority.rsplit('@').next().unwrap_or("");
    if host.contains('[') && !host.contains(']') { return None; }
    Some(s.to_string())
}

fn fenced(s: &str) -> Option<(String, Option<String>)> {
    if !s.starts_with("```") || !s.ends_with("```") || graphemes(s) <= 6 { return None; }
    let inner = &s[3..s.len() - 3];
    let nl = inner.find('\n')?;
    let lang = trim_ws(&inner[..nl]);
    let body = trim_nl(&inner[nl + 1..]);
    Some((body.to_string(), if lang.is_empty() { None } else { Some(lang.to_string()) }))
}

const IMAGE_EXTENSIONS: [&str; 8] = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"];

pub fn classify(c: &ClipboardContents, read_file: &dyn Fn(&str) -> Option<Vec<u8>>) -> Vec<PasteResult> {
    if !c.file_paths.is_empty() {
        return c.file_paths.iter().map(|path| {
            let ext = path.rsplit('.').next().unwrap_or("").to_lowercase();
            if IMAGE_EXTENSIONS.contains(&ext.as_str()) {
                if let Some(data) = read_file(path) { return PasteResult::Image(data, ext); }
            }
            PasteResult::File(path.clone())
        }).collect();
    }
    if let Some(data) = &c.image { return vec![PasteResult::Image(data.clone(), c.image_ext.clone())]; }
    if let Some(rows) = c.html.as_deref().and_then(rows_from_html) { return vec![PasteResult::Table(rows)]; }
    let plain = match c.plain.as_deref().map(trim_all) {
        Some(p) if !p.is_empty() => p,
        _ => return vec![],
    };
    if let Some(rows) = rows_from_tsv(plain) { return vec![PasteResult::Table(rows)]; }
    if let Some(url) = single_url(plain) { return vec![PasteResult::Link(url, None)]; }
    if let Some((body, lang)) = fenced(plain) { return vec![PasteResult::Code(body, lang)]; }
    vec![PasteResult::Text(plain.to_string())]
}

/// LinkTitle.parse: the fetch stays in the shell.
pub fn html_title(html: &str) -> Option<String> {
    let inner = patterns().title.captures(html)?;
    let decoded = decode_entities(&inner[1]);
    let text = decoded.split_whitespace().collect::<Vec<_>>().join(" ");
    if text.is_empty() { None } else { Some(text) }
}

pub const DEFAULT_WIDTH: i64 = 408;

/// Placement.block, for results that carry no bytes. The shell stores assets first.
pub fn place(result: &PasteResult, x: i64, y: i64, asset: Option<String>, size: Option<i64>) -> Block {
    let id = new_uuid();
    let mut b = match result {
        PasteResult::Text(s) => { let mut b = Block::new(id, BlockKind::Text, x, y, DEFAULT_WIDTH); b.text = Some(s.clone()); b }
        PasteResult::Code(s, lang) => { let mut b = Block::new(id, BlockKind::Code, x, y, DEFAULT_WIDTH); b.text = Some(s.clone()); b.language = lang.clone(); b }
        PasteResult::Link(url, title) => {
            let mut b = Block::new(id, BlockKind::Link, x, y, 300);
            b.text = Some(title.clone().unwrap_or_else(|| url.clone()));
            b.url = Some(url.clone());
            b
        }
        PasteResult::Table(rows) => {
            let mut b = Block::new(id, BlockKind::Table, x, y, 720.min(120 * (rows[0].len() as i64).max(2) + 24));
            b.rows = Some(rows.clone());
            b
        }
        PasteResult::Image(..) => { let mut b = Block::new(id, BlockKind::Image, x, y, 300); b.asset = Some(asset.unwrap_or_default()); b }
        PasteResult::File(path) => {
            let mut b = Block::new(id, BlockKind::File, x, y, 300);
            b.asset = Some(asset.unwrap_or_else(|| path.clone()));
            b.name = path.rsplit('/').next().map(String::from);
            b.size = Some(size.unwrap_or(0));
            b
        }
    };
    b.snap();
    b
}

/// Where a new block goes. With nothing wider to fill, the first free grid point below everything,
/// in the left column. Given a `width` (a monitor's paper, in canvas points), across it: columns a
/// default block apart, taking the one with the highest free spot, the leftmost on a tie.
pub fn next_free_point(pad: &Pad, width: Option<i64>, block_width: i64) -> (i64, i64) {
    let clear = |blocks: &mut dyn Iterator<Item = &Block>| -> i64 {
        blocks.map(|b| b.y + b.h.unwrap_or(120)).max().map(|y| snapped(y + GRID)).unwrap_or(GRID)
    };
    let mut best: Option<(i64, i64)> = None;
    if let Some(width) = width.filter(|w| *w >= GRID + block_width) {
        let mut x = GRID;
        while x <= width - block_width {
            let y = clear(&mut pad.blocks.iter().filter(|b| b.x < x + block_width && x < b.x + b.w));
            if best.map(|(_, by)| y < by).unwrap_or(true) { best = Some((x, y)); }
            x += DEFAULT_WIDTH + GRID;
        }
    }
    best.unwrap_or((GRID, clear(&mut pad.blocks.iter())))
}

/// MonitorFit: (scale, paper width, paper height).
pub fn monitor_fit(content: (f64, f64), space: (f64, f64), least: f64, most: f64) -> (f64, f64, f64) {
    let fit = (space.0 / content.0).min(space.1 / content.1);
    let scale = most.min(least.max(fit));
    (scale, content.0.max(space.0 / scale), content.1.max(space.1 / scale))
}
