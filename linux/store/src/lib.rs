//! Mirrors shared/schema/pad.schema.json. Keep field names identical to the Swift and TS models.

use chrono::{DateTime, Local, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const GRID: i64 = 24;

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("bad id: {0}")]
    BadId(String),
}

pub type Result<T> = std::result::Result<T, StoreError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BlockKind { Text, Table, Image, File, Link, Code, Divider }

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Block {
    pub id: String,
    pub kind: BlockKind,
    pub x: i64,
    pub y: i64,
    pub w: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub h: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub rows: Option<Vec<Vec<String>>>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub asset: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub size: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub caption: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub language: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TodoStatus { Open, Done, Deferred }

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Todo {
    pub id: String,
    pub text: String,
    pub status: TodoStatus,
    #[serde(rename = "createdAt")] pub created_at: DateTime<Utc>,
    #[serde(rename = "carriedFrom", default)] pub carried_from: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Pad {
    pub v: u8,
    pub id: String,
    #[serde(default)] pub date: Option<String>,
    #[serde(default)] pub title: String,
    #[serde(default)] pub tag: String,
    #[serde(default)] pub pinned: bool,
    #[serde(rename = "createdAt")] pub created_at: DateTime<Utc>,
    #[serde(rename = "updatedAt")] pub updated_at: DateTime<Utc>,
    #[serde(default)] pub blocks: Vec<Block>,
    #[serde(default)] pub todos: Vec<Todo>,
}

impl Pad {
    pub fn daily(day: &str, now: DateTime<Utc>) -> Pad {
        Pad { v: 1, id: day.to_string(), date: Some(day.to_string()), title: String::new(), tag: String::new(),
              pinned: false, created_at: now, updated_at: now, blocks: vec![], todos: vec![] }
    }
}

/// Midnight rule: open and deferred rows copy over as open, done rows stay. createdAt is kept.
pub fn carry(previous: &Pad, mut target: Pad) -> Pad {
    let mut carried: Vec<Todo> = previous.todos.iter()
        .filter(|t| !t.text.is_empty() && t.status != TodoStatus::Done)
        .map(|t| Todo { id: uuid::Uuid::new_v4().to_string(), text: t.text.clone(), status: TodoStatus::Open,
                        created_at: t.created_at, carried_from: Some(previous.id.clone()) })
        .collect();
    carried.append(&mut target.todos);
    target.todos = carried;
    target
}

/// The latest dated, unpinned pad strictly before `day`.
pub fn rollover_source<'a>(day: &str, pads: &'a [Pad]) -> Option<&'a Pad> {
    pads.iter()
        .filter(|p| !p.pinned && p.date.as_deref().map(|d| d < day).unwrap_or(false))
        .max_by(|a, b| a.date.cmp(&b.date))
}

pub fn today_key() -> String { Local::now().format("%Y-%m-%d").to_string() }

pub fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 80 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

pub struct Store { pub root: PathBuf }

impl Store {
    pub fn open(root: impl Into<PathBuf>) -> Result<Store> {
        let root = root.into();
        fs::create_dir_all(root.join("pads"))?;
        fs::create_dir_all(root.join("assets"))?;
        Ok(Store { root })
    }

    fn pad_path(&self, id: &str) -> Result<PathBuf> {
        if !valid_id(id) { return Err(StoreError::BadId(id.to_string())); }
        Ok(self.root.join("pads").join(format!("{id}.json")))
    }

    pub fn list(&self) -> Result<Vec<Pad>> {
        let mut pads: Vec<Pad> = fs::read_dir(self.root.join("pads"))?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "json").unwrap_or(false))
            .filter_map(|e| fs::read(e.path()).ok())
            .filter_map(|b| serde_json::from_slice::<Pad>(&b).ok())
            .collect();
        pads.sort_by(|a, b| b.date.cmp(&a.date));
        Ok(pads)
    }

    pub fn load(&self, id: &str) -> Result<Option<Pad>> {
        let p = self.pad_path(id)?;
        if !p.exists() { return Ok(None); }
        Ok(Some(serde_json::from_slice(&fs::read(p)?)?))
    }

    pub fn save(&self, pad: &Pad) -> Result<()> {
        let mut pad = pad.clone();
        pad.updated_at = Utc::now();
        let path = self.pad_path(&pad.id)?;
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_vec_pretty(&pad)?)?;
        fs::rename(tmp, path)?;
        Ok(())
    }

    pub fn delete(&self, id: &str) -> Result<()> {
        fs::remove_file(self.pad_path(id)?)?;
        Ok(())
    }

    /// Today's pad, created with rollover when missing.
    pub fn today(&self) -> Result<Pad> {
        let key = today_key();
        if let Some(p) = self.load(&key)? { return Ok(p); }
        let mut pad = Pad::daily(&key, Utc::now());
        let pads = self.list()?;
        if let Some(prev) = rollover_source(&key, &pads) { pad = carry(prev, pad); }
        self.save(&pad)?;
        Ok(pad)
    }

    /// Writes bytes under assets/ and returns the store-relative path.
    pub fn store_asset(&self, bytes: &[u8], ext: &str) -> Result<String> {
        let ext: String = ext.chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect::<String>().to_lowercase();
        let rel = format!("assets/{}.{}", uuid::Uuid::new_v4(), if ext.is_empty() { "bin" } else { &ext });
        fs::write(self.root.join(&rel), bytes)?;
        Ok(rel)
    }

    pub fn import_file(&self, path: &Path) -> Result<(String, String, u64)> {
        let bytes = fs::read(path)?;
        let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
        let rel = self.store_asset(&bytes, ext)?;
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("file").to_string();
        Ok((rel, name, bytes.len() as u64))
    }

    pub fn asset_path(&self, rel: &str) -> Option<PathBuf> {
        let rel = rel.strip_prefix("assets/")?;
        if rel.contains('/') || rel.contains("..") { return None; }
        Some(self.root.join("assets").join(rel))
    }
}

/// `<title>` text from an HTML document, entities decoded and whitespace collapsed.
pub fn html_title(html: &str) -> Option<String> {
    let lower = html.to_ascii_lowercase();
    let start = lower.find("<title")?;
    let open_end = lower[start..].find('>')? + start + 1;
    let close = lower[open_end..].find("</title>")? + open_end;
    let raw = &html[open_end..close];
    let text = raw.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'").replace("&nbsp;", " ");
    let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if text.is_empty() { None } else { Some(text) }
}

/// Case-insensitive search across title, tag, block text and to-do text.
pub fn matches(pad: &Pad, query: &str) -> bool {
    let q = query.trim().to_lowercase();
    if q.is_empty() { return true; }
    let hit = |s: &str| s.to_lowercase().contains(&q);
    hit(&pad.title) || hit(&pad.tag) || hit(&pad.id)
        || pad.blocks.iter().any(|b| b.text.as_deref().map(hit).unwrap_or(false)
            || b.name.as_deref().map(hit).unwrap_or(false)
            || b.url.as_deref().map(hit).unwrap_or(false)
            || b.caption.as_deref().map(hit).unwrap_or(false)
            || b.rows.as_ref().map(|r| r.iter().flatten().any(|c| hit(c))).unwrap_or(false))
        || pad.todos.iter().any(|t| hit(&t.text))
}

/// The day a pad belongs to, for sorting and labels.
pub fn parse_day(key: &str) -> Option<NaiveDate> { NaiveDate::parse_from_str(key, "%Y-%m-%d").ok() }

#[cfg(test)]
mod tests {
    use super::*;

    fn todo(text: &str, status: TodoStatus) -> Todo {
        Todo { id: text.to_string(), text: text.to_string(), status, created_at: Utc::now(), carried_from: None }
    }

    #[test]
    fn carries_open_and_deferred_only() {
        let mut prev = Pad::daily("2026-10-11", Utc::now());
        prev.todos = vec![todo("a", TodoStatus::Open), todo("b", TodoStatus::Done), todo("c", TodoStatus::Deferred), todo("", TodoStatus::Open)];
        let next = carry(&prev, Pad::daily("2026-10-12", Utc::now()));
        let texts: Vec<_> = next.todos.iter().map(|t| t.text.as_str()).collect();
        assert_eq!(texts, vec!["a", "c"]);
        assert!(next.todos.iter().all(|t| t.status == TodoStatus::Open && t.carried_from.as_deref() == Some("2026-10-11")));
    }

    #[test]
    fn rollover_source_is_latest_earlier() {
        let mk = |d: &str| Pad::daily(d, Utc::now());
        let mut pinned = Pad::daily("x", Utc::now()); pinned.date = None; pinned.pinned = true; pinned.id = "ideas".into();
        let pads = vec![mk("2026-10-09"), mk("2026-10-11"), mk("2026-10-13"), pinned];
        assert_eq!(rollover_source("2026-10-12", &pads).unwrap().id, "2026-10-11");
    }

    #[test]
    fn round_trips_shared_sample() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../shared/samples/2026-10-12.json");
        let pad: Pad = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
        assert_eq!(pad.blocks.len(), 4);
        assert_eq!(pad.todos[2].status, TodoStatus::Deferred);
        let again: Pad = serde_json::from_str(&serde_json::to_string(&pad).unwrap()).unwrap();
        assert_eq!(again, pad);
    }

    #[test]
    fn store_creates_today_with_rollover() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(dir.path()).unwrap();
        let mut prev = Pad::daily("2000-01-01", Utc::now());
        prev.todos = vec![todo("carry me", TodoStatus::Open)];
        store.save(&prev).unwrap();
        let today = store.today().unwrap();
        assert_eq!(today.todos[0].text, "carry me");
        assert!(store.load(&today.id).unwrap().is_some());
        assert!(store.load("../etc/passwd").is_err());
    }

    #[test]
    fn title_and_search() {
        assert_eq!(html_title("<html><head><TITLE>  Tauri &amp;\n  friends </title>"), Some("Tauri & friends".into()));
        assert_eq!(html_title("<p>no title</p>"), None);
        let mut pad = Pad::daily("2026-10-12", Utc::now());
        pad.blocks.push(Block { id: "b".into(), kind: BlockKind::Table, x: 0, y: 0, w: 96, h: None, text: None,
            rows: Some(vec![vec!["Item".into(), "Berlin".into()]]), asset: None, name: None, size: None, url: None, caption: None, language: None });
        pad.todos.push(todo("Call Mum", TodoStatus::Open));
        assert!(matches(&pad, "berlin"));
        assert!(matches(&pad, "mum"));
        assert!(!matches(&pad, "paris"));
    }

    #[test]
    fn asset_paths_stay_inside_store() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(dir.path()).unwrap();
        let rel = store.store_asset(b"png", "png").unwrap();
        assert!(store.asset_path(&rel).unwrap().exists());
        assert!(store.asset_path("assets/../pads/x.json").is_none());
        assert!(store.asset_path("pads/x.json").is_none());
    }
}
