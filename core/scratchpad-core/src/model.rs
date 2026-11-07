//! Block, Todo, Pad, SheetID, Tags. Reads every shape the Swift decoder reads.
use crate::dates::Date;
use crate::text::{graphemes, is_ws, lines, prefix, trim_all, trim_ws};
use serde::de::{self, Deserializer};
use serde::Deserialize;
use std::collections::BTreeMap;

/// Fields this build doesn't know, kept so an older core can't delete what a newer one wrote.
pub type Extras = BTreeMap<String, serde_json::Value>;

pub const GRID: i64 = 24;
pub const MIN_WIDTH: i64 = 48;
pub const MIN_HEIGHT: i64 = 24;
pub const DEFAULT_FONT_SIZE: i64 = 14;
pub const FORMAT_VERSION: i64 = 2;

#[derive(Clone, Copy, PartialEq, Eq, Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BlockKind { Text, Table, Image, File, Link, Code, Divider }

impl BlockKind {
    pub fn name(self) -> &'static str {
        match self {
            BlockKind::Text => "text", BlockKind::Table => "table", BlockKind::Image => "image", BlockKind::File => "file",
            BlockKind::Link => "link", BlockKind::Code => "code", BlockKind::Divider => "divider",
        }
    }
    pub fn from_name(s: &str) -> Option<BlockKind> {
        Some(match s {
            "text" => BlockKind::Text, "table" => BlockKind::Table, "image" => BlockKind::Image, "file" => BlockKind::File,
            "link" => BlockKind::Link, "code" => BlockKind::Code, "divider" => BlockKind::Divider,
            _ => return None,
        })
    }
    pub fn label(self) -> String {
        let n = self.name();
        format!("{}{}", n[..1].to_uppercase(), &n[1..])
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum BlockFont { Sans, Serif, Mono, Hand }

impl BlockFont {
    pub fn name(self) -> &'static str {
        match self { BlockFont::Sans => "sans", BlockFont::Serif => "serif", BlockFont::Mono => "mono", BlockFont::Hand => "hand" }
    }
    pub fn from_name(s: &str) -> BlockFont {
        match s { "serif" => BlockFont::Serif, "mono" => BlockFont::Mono, "hand" => BlockFont::Hand, _ => BlockFont::Sans }
    }
}

/// `try? decodeIfPresent`: anything unreadable is the default.
fn lenient_font<'de, D: Deserializer<'de>>(d: D) -> Result<BlockFont, D::Error> {
    let v = serde_json::Value::deserialize(d)?;
    Ok(BlockFont::from_name(v.as_str().unwrap_or("")))
}

fn sans() -> BlockFont { BlockFont::Sans }

fn null_as_default<'de, D: Deserializer<'de>, T: Default + Deserialize<'de>>(d: D) -> Result<T, D::Error> {
    Ok(Option::<T>::deserialize(d)?.unwrap_or_default())
}

/// A whole number, as JSONDecoder reads one: `12.0` counts, `12.5` doesn't.
#[derive(Clone, Copy)]
struct Whole(i64);

impl<'de> Deserialize<'de> for Whole {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Whole, D::Error> {
        let n = serde_json::Number::deserialize(d)?;
        if let Some(v) = n.as_i64() { return Ok(Whole(v)); }
        match n.as_f64() {
            Some(v) if v.fract() == 0.0 && v.abs() < 9.0e15 => Ok(Whole(v as i64)),
            _ => Err(de::Error::custom("not a whole number")),
        }
    }
}

fn whole<'de, D: Deserializer<'de>>(d: D) -> Result<i64, D::Error> { Ok(Whole::deserialize(d)?.0) }

fn opt_whole<'de, D: Deserializer<'de>>(d: D) -> Result<Option<i64>, D::Error> {
    Ok(Option::<Whole>::deserialize(d)?.map(|w| w.0))
}

fn opt_wholes<'de, D: Deserializer<'de>>(d: D) -> Result<Option<Vec<i64>>, D::Error> {
    Ok(Option::<Vec<Whole>>::deserialize(d)?.map(|v| v.into_iter().map(|w| w.0).collect()))
}

fn font_size<'de, D: Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    Ok(Option::<Whole>::deserialize(d)?.map(|w| w.0).unwrap_or(DEFAULT_FONT_SIZE).clamp(10, 48))
}

fn default_font_size() -> i64 { DEFAULT_FONT_SIZE }

fn rotation<'de, D: Deserializer<'de>>(d: D) -> Result<f64, D::Error> {
    Ok(normalized_rotation(Option::<f64>::deserialize(d)?.unwrap_or(0.0)))
}

#[derive(Clone, PartialEq, Debug, Deserialize)]
pub struct Block {
    pub id: String,
    pub kind: BlockKind,
    #[serde(deserialize_with = "whole")] pub x: i64,
    #[serde(deserialize_with = "whole")] pub y: i64,
    #[serde(deserialize_with = "whole")] pub w: i64,
    #[serde(default, deserialize_with = "opt_whole")] pub h: Option<i64>,
    #[serde(default)] pub text: Option<String>,
    #[serde(default)] pub rows: Option<Vec<Vec<String>>>,
    #[serde(default)] pub asset: Option<String>,
    #[serde(default)] pub name: Option<String>,
    #[serde(default, deserialize_with = "opt_whole")] pub size: Option<i64>,
    #[serde(default)] pub url: Option<String>,
    #[serde(default)] pub caption: Option<String>,
    #[serde(default)] pub language: Option<String>,
    #[serde(default, deserialize_with = "rotation")] pub rotation: f64,
    #[serde(default = "sans", deserialize_with = "lenient_font")] pub font: BlockFont,
    #[serde(rename = "fontSize", default = "default_font_size", deserialize_with = "font_size")] pub font_size: i64,
    #[serde(default, deserialize_with = "null_as_default")] pub bold: bool,
    #[serde(default, deserialize_with = "null_as_default")] pub italic: bool,
    #[serde(rename = "colWidths", default, deserialize_with = "opt_wholes")] pub col_widths: Option<Vec<i64>>,
    #[serde(flatten)] pub extra: Extras,
}

pub fn snapped(v: i64) -> i64 {
    (v as f64 / GRID as f64).round() as i64 * GRID
}

/// Degrees into (-180, 180], rounded to 0.1.
pub fn normalized_rotation(degrees: f64) -> f64 {
    if !degrees.is_finite() { return 0.0; }
    let mut r = degrees % 360.0;
    if r <= -180.0 { r += 360.0; }
    if r > 180.0 { r -= 360.0; }
    r = (r * 10.0).round() / 10.0;
    if r == -180.0 { 180.0 } else if r == 0.0 { 0.0 } else { r }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Corner { TopLeft, TopRight, BottomLeft, BottomRight }

impl Corner {
    fn is_left(self) -> bool { matches!(self, Corner::TopLeft | Corner::BottomLeft) }
    fn is_top(self) -> bool { matches!(self, Corner::TopLeft | Corner::TopRight) }
}

impl Block {
    pub fn new(id: String, kind: BlockKind, x: i64, y: i64, w: i64) -> Block {
        Block { id, kind, x, y, w, h: None, text: None, rows: None, asset: None, name: None, size: None, url: None, caption: None,
                language: None, rotation: 0.0, font: BlockFont::Sans, font_size: DEFAULT_FONT_SIZE, bold: false, italic: false, col_widths: None,
                extra: Extras::new() }
    }

    pub fn snap(&mut self) {
        self.x = snapped(self.x).max(0);
        self.y = snapped(self.y).max(0);
        self.w = snapped(self.w).max(2 * GRID);
    }

    pub fn rotate_step(&mut self) { self.rotation = normalized_rotation(self.rotation + 15.0); }

    pub fn duplicated(&self, new_id: String) -> Block {
        let mut b = self.clone();
        b.id = new_id;
        b.x += GRID;
        b.y += GRID;
        b
    }

    pub fn resized(&self, corner: Corner, dx: f64, dy: f64, start_height: f64, keep_aspect: bool) -> Block {
        let mut b = self.clone();
        let w0 = self.w as f64;
        let h0 = (MIN_HEIGHT as f64).max(start_height);
        let mut nw = if corner.is_left() { w0 - dx } else { w0 + dx };
        let mut nh = if corner.is_top() { h0 - dy } else { h0 + dy };
        if keep_aspect && w0 > 0.0 { nh = nw * h0 / w0; }
        nw = nw.max(MIN_WIDTH as f64);
        nh = nh.max(MIN_HEIGHT as f64);
        if keep_aspect && w0 > 0.0 { nh = (MIN_HEIGHT as f64).max(nw * h0 / w0); }
        if corner.is_left() { b.x = (self.x as f64 + w0 - nw).round() as i64; }
        if corner.is_top() { b.y = (self.y as f64 + h0 - nh).round() as i64; }
        b.w = nw.round() as i64;
        b.h = Some(nh.round() as i64);
        b.x = b.x.max(0);
        b.y = b.y.max(0);
        b
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TodoStatus { Open, Done, Deferred }

impl TodoStatus {
    pub fn name(self) -> &'static str {
        match self { TodoStatus::Open => "open", TodoStatus::Done => "done", TodoStatus::Deferred => "deferred" }
    }
    pub fn from_name(s: &str) -> Option<TodoStatus> {
        Some(match s { "open" => TodoStatus::Open, "done" => TodoStatus::Done, "deferred" => TodoStatus::Deferred, _ => return None })
    }
    pub fn next(self) -> TodoStatus {
        match self { TodoStatus::Open => TodoStatus::Done, TodoStatus::Done => TodoStatus::Deferred, TodoStatus::Deferred => TodoStatus::Open }
    }
}

fn date<'de, D: Deserializer<'de>>(d: D) -> Result<Date, D::Error> {
    let s = <std::borrow::Cow<str>>::deserialize(d)?;
    Date::parse(&s).ok_or_else(|| de::Error::custom("bad date"))
}

fn opt_date<'de, D: Deserializer<'de>>(d: D) -> Result<Option<Date>, D::Error> {
    match Option::<std::borrow::Cow<str>>::deserialize(d)? {
        None => Ok(None),
        Some(s) => Date::parse(&s).map(Some).ok_or_else(|| de::Error::custom("bad date")),
    }
}

#[derive(Clone, PartialEq, Debug, Deserialize)]
pub struct Todo {
    pub id: String,
    pub text: String,
    pub status: TodoStatus,
    #[serde(rename = "createdAt", deserialize_with = "date")] pub created_at: Date,
    #[serde(rename = "carriedFrom", default)] pub carried_from: Option<String>,
    #[serde(flatten)] pub extra: Extras,
}

impl Todo {
    pub fn is_filled(&self) -> bool { !trim_all(&self.text).is_empty() }
    pub fn is_overdue(&self, now: Date) -> bool {
        self.status == TodoStatus::Open && self.is_filled() && now.0 - self.created_at.0 >= 3 * 86_400_000
    }
}

#[derive(Deserialize)]
struct RawPad {
    /// Always written as 2, so it isn't an unknown field.
    #[allow(dead_code)] #[serde(default)] v: Option<serde_json::Value>,
    id: String,
    #[serde(default)] date: Option<String>,
    #[serde(default)] title: Option<String>,
    #[serde(default)] tag: Option<String>,
    #[serde(default)] tags: Option<Vec<String>>,
    #[serde(default)] pinned: Option<bool>,
    #[serde(rename = "createdAt", default, deserialize_with = "opt_date")] created_at: Option<Date>,
    #[serde(rename = "updatedAt", default, deserialize_with = "opt_date")] updated_at: Option<Date>,
    #[serde(default)] blocks: Option<Vec<Block>>,
    #[serde(default)] todos: Option<Vec<Todo>>,
    #[serde(flatten)] extra: Extras,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Pad {
    pub id: String,
    pub date: Option<String>,
    pub title: String,
    pub tags: Vec<String>,
    pub pinned: bool,
    pub created_at: Date,
    pub updated_at: Date,
    pub blocks: Vec<Block>,
    pub todos: Vec<Todo>,
    pub extra: Extras,
}

impl<'de> Deserialize<'de> for Pad {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Pad, D::Error> {
        let r = RawPad::deserialize(d)?;
        let mut raw = Vec::new();
        if let Some(t) = r.tag { raw.push(t); }
        raw.extend(r.tags.unwrap_or_default());
        let created_at = r.created_at.unwrap_or_else(Date::now);
        Ok(Pad {
            pinned: r.pinned.unwrap_or(r.date.is_none()),
            id: r.id, date: r.date, title: r.title.unwrap_or_default(), tags: tags_normalized(&raw),
            created_at, updated_at: r.updated_at.unwrap_or(created_at),
            blocks: r.blocks.unwrap_or_default(), todos: r.todos.unwrap_or_default(), extra: r.extra,
        })
    }
}

/// The shape the file has, for the Tauri bridge.
impl serde::Serialize for Pad {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let value: serde_json::Value = serde_json::from_slice(&crate::json::encode_pad(self)).map_err(serde::ser::Error::custom)?;
        value.serialize(s)
    }
}

impl Pad {
    pub fn new(id: String, date: Option<String>, title: String, tags: &[String], pinned: bool, now: Date) -> Pad {
        Pad { id, date, title, tags: tags_normalized(tags), pinned, created_at: now, updated_at: now, blocks: vec![], todos: vec![], extra: Extras::new() }
    }

    pub fn from_json(bytes: &[u8]) -> Result<Pad, serde_json::Error> { serde_json::from_slice(bytes) }

    pub fn display_title(&self) -> String {
        let t = trim_all(&self.title);
        if t.is_empty() { "Untitled sheet".into() } else { t.to_string() }
    }

    pub fn preview(&self) -> Option<String> {
        let mut blocks: Vec<&Block> = self.blocks.iter().filter(|b| matches!(b.kind, BlockKind::Text | BlockKind::Code)).collect();
        blocks.sort_by_key(|b| (b.y, b.x));
        let texts = blocks.iter().filter_map(|b| b.text.as_deref())
            .chain(self.todos.iter().filter(|t| t.is_filled()).map(|t| t.text.as_str()));
        for t in texts {
            if let Some(line) = lines(t).map(trim_ws).find(|l| !l.is_empty()) {
                return Some(prefix(line, 80));
            }
        }
        None
    }

    pub fn matches(&self, query: &str) -> bool {
        let lowered = trim_ws(query).to_lowercase();
        let q = lowered.strip_prefix('#').unwrap_or(&lowered);
        if q.is_empty() { return true; }
        let hit = |s: &str| s.to_lowercase().contains(q);
        let some = |s: &Option<String>| s.as_deref().map(hit).unwrap_or(false);
        hit(&self.title) || self.tags.iter().any(|t| hit(t)) || hit(&self.id)
            || self.blocks.iter().any(|b| some(&b.text) || some(&b.name) || some(&b.url) || some(&b.caption)
                || b.rows.as_ref().map(|r| r.iter().any(|row| row.iter().any(|c| hit(c)))).unwrap_or(false))
            || self.todos.iter().any(|t| hit(&t.text))
    }

    pub fn move_todo(&mut self, id: &str, before: Option<&str>) {
        if Some(id) == before { return; }
        let Some(moving) = self.todos.iter().find(|t| t.id == id).cloned() else { return };
        self.todos.retain(|t| t.id != id);
        match before.and_then(|b| self.todos.iter().position(|t| t.id == b)) {
            Some(i) => self.todos.insert(i, moving),
            None => self.todos.push(moving),
        }
    }

    fn filled(&self) -> impl Iterator<Item = &Todo> { self.todos.iter().filter(|t| t.is_filled()) }
    pub fn done_count(&self) -> usize { self.filled().filter(|t| t.status == TodoStatus::Done).count() }
    pub fn open_count(&self) -> usize { self.filled().filter(|t| t.status == TodoStatus::Open).count() }
    pub fn filled_count(&self) -> usize { self.filled().count() }
    pub fn carry_count(&self) -> usize { self.filled().filter(|t| t.status != TodoStatus::Done).count() }
    pub fn count_label(&self) -> String { format!("{} of {} done", self.done_count(), self.filled_count()) }
    pub fn footer_label(&self) -> String {
        if self.filled_count() == 0 { return "Nothing here yet".into(); }
        if self.carry_count() == 0 { return "Nothing to carry. Nice.".into(); }
        format!("{} open will carry to tomorrow", self.carry_count())
    }

    /// Drops empty rows, for writing to disk.
    pub fn compacted(&self) -> Pad {
        let mut p = self.clone();
        p.todos.retain(|t| !t.text.is_empty());
        p
    }

    pub fn duplicate(&self, new_id: String, now: Date, fresh_id: &mut dyn FnMut() -> String) -> Pad {
        let mut p = Pad::new(new_id, self.date.clone(), format!("{} copy", self.title), &self.tags, self.pinned, now);
        p.blocks = self.blocks.iter().map(|b| { let mut c = b.clone(); c.id = fresh_id(); c }).collect();
        p.todos = self.todos.iter().filter(|t| t.status == TodoStatus::Open && t.is_filled()).map(|t| Todo {
            id: fresh_id(), text: t.text.clone(), status: TodoStatus::Open, created_at: t.created_at, carried_from: t.carried_from.clone(),
            extra: t.extra.clone(),
        }).collect();
        p
    }

    pub fn moved(&self, day: &str) -> Pad {
        let mut p = self.clone();
        p.date = Some(day.to_string());
        p.pinned = false;
        p
    }
}

const ALPHABET: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyz";

const ALPHABET_LEN: u8 = 36;

/// Six lowercase base36 characters. Two devices make ids without talking, so this needs real randomness.
pub fn suffix() -> String {
    uuid::Uuid::new_v4().as_bytes().iter().take(6).map(|b| ALPHABET[(*b % ALPHABET_LEN) as usize] as char).collect()
}

/// Uppercase, as `UUID().uuidString`.
pub fn new_uuid() -> String { uuid::Uuid::new_v4().to_string().to_uppercase() }

pub fn make_sheet_id(day: &str) -> String { format!("{}-{}", day, suffix()) }

pub fn is_valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 80 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

pub fn is_dated_id(id: &str) -> bool {
    let b = id.as_bytes();
    b.len() == 17 && b[4] == b'-' && b[7] == b'-' && b[10] == b'-'
        && [0, 1, 2, 3, 5, 6, 8, 9].iter().all(|i| b[*i].is_ascii_digit())
        && b[11..].iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
}

pub fn slug(title: &str, existing: &std::collections::HashSet<String>) -> String {
    let lowered = title.to_lowercase();
    let mut s = String::new();
    let mut gap = false;
    for c in lowered.chars() {
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            if gap { s.push('-'); gap = false; }
            s.push(c);
        } else {
            gap = true;
        }
    }
    if gap { s.push('-'); }
    let mut s = s.trim_matches('-').to_string();
    if s.len() > 60 { s = s[..60].trim_matches('-').to_string(); }
    if s.is_empty() { s = format!("sheet-{}", suffix()); }
    let (mut candidate, mut n) = (s.clone(), 2);
    while existing.contains(&candidate) {
        candidate = format!("{}-{}", s, n);
        n += 1;
    }
    candidate
}

pub fn tag_normalize(raw: &str) -> String {
    let lowered = trim_all(raw).to_lowercase();
    let s: String = lowered.trim_start_matches('#').chars()
        .filter(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == '_' || *c == '-').collect();
    s.trim_start_matches(['_', '-']).to_string()
}

pub fn tags_normalized(list: &[String]) -> Vec<String> {
    let mut out: Vec<String> = Vec::with_capacity(list.len());
    for t in list {
        let n = tag_normalize(t);
        if !n.is_empty() && !out.contains(&n) { out.push(n); }
    }
    out
}

/// Tags with sheet counts, most used first then A to Z.
pub fn tag_counts(pads: &[Pad]) -> Vec<(String, usize)> {
    let mut m = std::collections::HashMap::new();
    for p in pads { for t in &p.tags { *m.entry(t.clone()).or_insert(0usize) += 1; } }
    let mut v: Vec<(String, usize)> = m.into_iter().collect();
    v.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    v
}

pub fn tag_suggestions(prefix_text: &str, pads: &[Pad], excluding: &[String]) -> Vec<(String, usize)> {
    let p = tag_normalize(prefix_text);
    tag_counts(pads).into_iter().filter(|(t, _)| !excluding.contains(t) && (p.is_empty() || t.starts_with(&p))).collect()
}

/// TableLayout, here because it reads a Block.
pub fn table_widths(block: &Block) -> Vec<i64> {
    let cols = block.rows.as_ref().and_then(|r| r.iter().map(|x| x.len()).max()).unwrap_or(1).max(1);
    if let Some(stored) = block.col_widths.as_ref().filter(|s| !s.is_empty()) {
        let fallback = *stored.last().unwrap();
        return (0..cols).map(|i| stored.get(i).copied().unwrap_or(fallback).max(40)).collect();
    }
    vec![(block.w / cols as i64).max(40); cols]
}

pub fn fit_width(column: usize, rows: &[Vec<String>]) -> i64 {
    let mut eval = crate::formula::TableEvaluator::new(rows);
    let mut longest = 0;
    for (r, row) in rows.iter().enumerate() {
        let Some(raw) = row.get(column) else { continue };
        let n = if crate::formula::is_formula(raw) { graphemes(&eval.display(r, column)) } else { graphemes(raw) };
        longest = longest.max(n);
    }
    ((7.5 * longest as f64 + 20.0).round() as i64).clamp(40, 480)
}

pub fn has_only_spaces(s: &str) -> bool { s.chars().all(is_ws) }
