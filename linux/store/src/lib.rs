//! Mirrors shared/schema/pad.schema.json (v2) and docs/v0.2-spec.md. Keep field names identical to the Swift and TS models.

use base64::Engine;
use chrono::{DateTime, Local, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const GRID: i64 = 24;
pub const FORMAT_VERSION: u8 = 2;

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("bad id: {0}")]
    BadId(String),
    #[error("not a Scratchpad archive")]
    BadArchive,
}

pub type Result<T> = std::result::Result<T, StoreError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BlockKind { Text, Table, Image, File, Link, Code, Divider }

fn is_zero(v: &f64) -> bool { *v == 0.0 }
fn is_false(v: &bool) -> bool { !*v }

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
    #[serde(default, skip_serializing_if = "is_zero")] pub rotation: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub font: Option<String>,
    #[serde(rename = "fontSize", default, skip_serializing_if = "Option::is_none")] pub font_size: Option<i64>,
    #[serde(default, skip_serializing_if = "is_false")] pub bold: bool,
    #[serde(default, skip_serializing_if = "is_false")] pub italic: bool,
    #[serde(rename = "colWidths", default, skip_serializing_if = "Option::is_none")] pub col_widths: Option<Vec<i64>>,
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
    #[serde(default)] pub tags: Vec<String>,
    /// v1 only. Read, folded into `tags`, never written.
    #[serde(default, skip_serializing)] pub tag: Option<String>,
    #[serde(default)] pub pinned: bool,
    #[serde(rename = "createdAt")] pub created_at: DateTime<Utc>,
    #[serde(rename = "updatedAt")] pub updated_at: DateTime<Utc>,
    #[serde(default)] pub blocks: Vec<Block>,
    #[serde(default)] pub todos: Vec<Todo>,
}

/// Lowercase, strip `#` and spaces, keep [a-z0-9_-].
pub fn normalize_tag(t: &str) -> String {
    t.trim().trim_start_matches('#').to_lowercase().chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_').collect()
}

impl Pad {
    pub fn new_dated(day: &str, now: DateTime<Utc>) -> Pad {
        Pad { v: FORMAT_VERSION, id: new_sheet_id(day), date: Some(day.to_string()), title: String::new(), tags: vec![], tag: None,
              pinned: false, created_at: now, updated_at: now, blocks: vec![], todos: vec![] }
    }

    /// v1 to v2: fold `tag` into `tags`, normalise tags, set v.
    pub fn migrate(mut self) -> Pad {
        if let Some(t) = self.tag.take() {
            let t = normalize_tag(&t);
            if !t.is_empty() && !self.tags.contains(&t) { self.tags.insert(0, t); }
        }
        let mut seen = Vec::new();
        for t in self.tags.drain(..).map(|t| normalize_tag(&t)).filter(|t| !t.is_empty()) {
            if !seen.contains(&t) { seen.push(t); }
        }
        self.tags = seen;
        self.v = FORMAT_VERSION;
        self
    }
}

/// `YYYY-MM-DD-xxxxxx`, six lowercase base36 chars.
pub fn new_sheet_id(day: &str) -> String {
    const A: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    let bytes = uuid::Uuid::new_v4().into_bytes();
    let suffix: String = bytes.iter().take(6).map(|b| A[(*b as usize) % 36] as char).collect();
    format!("{day}-{suffix}")
}

/// Midnight rule across sheets: open and deferred rows from every source copy over as open. createdAt is kept.
pub fn carry(sources: &[&Pad], mut target: Pad) -> Pad {
    let mut carried: Vec<Todo> = sources.iter().flat_map(|p| p.todos.iter()
        .filter(|t| !t.text.trim().is_empty() && t.status != TodoStatus::Done)
        .map(move |t| Todo { id: uuid::Uuid::new_v4().to_string(), text: t.text.clone(), status: TodoStatus::Open,
                             created_at: t.created_at, carried_from: Some(p.id.clone()) }))
        .collect();
    carried.append(&mut target.todos);
    target.todos = carried;
    target
}

/// Every unpinned sheet of the latest date strictly before `day`.
pub fn rollover_sources<'a>(day: &str, pads: &'a [Pad]) -> Vec<&'a Pad> {
    let latest = pads.iter().filter(|p| !p.pinned).filter_map(|p| p.date.as_deref()).filter(|d| *d < day).max();
    match latest {
        Some(d) => pads.iter().filter(|p| !p.pinned && p.date.as_deref() == Some(d)).collect(),
        None => vec![],
    }
}

pub fn today_key() -> String { Local::now().format("%Y-%m-%d").to_string() }

pub fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 80 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Archive {
    pub format: String,
    pub v: u8,
    #[serde(rename = "exportedAt")] pub exported_at: DateTime<Utc>,
    pub sheets: Vec<Pad>,
    pub assets: BTreeMap<String, String>,
}

#[derive(Debug, Serialize, Default, PartialEq)]
pub struct ImportSummary { pub sheets: usize, pub assets: usize }

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

    /// Newest date first, pinned last; same date by most recently updated.
    pub fn list(&self) -> Result<Vec<Pad>> {
        let mut pads: Vec<Pad> = fs::read_dir(self.root.join("pads"))?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "json").unwrap_or(false))
            .filter_map(|e| fs::read(e.path()).ok())
            .filter_map(|b| serde_json::from_slice::<Pad>(&b).ok())
            .map(Pad::migrate)
            .collect();
        pads.sort_by(|a, b| b.date.cmp(&a.date).then(b.updated_at.cmp(&a.updated_at)));
        Ok(pads)
    }

    pub fn load(&self, id: &str) -> Result<Option<Pad>> {
        let p = self.pad_path(id)?;
        if !p.exists() { return Ok(None); }
        Ok(Some(serde_json::from_slice::<Pad>(&fs::read(p)?)?.migrate()))
    }

    pub fn save(&self, pad: &Pad) -> Result<()> {
        let mut pad = pad.clone().migrate();
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

    /// The most recently updated sheet dated today, or a new one carrying over from the latest earlier day.
    pub fn today(&self) -> Result<Pad> {
        self.today_for(&today_key())
    }

    pub fn today_for(&self, key: &str) -> Result<Pad> {
        let pads = self.list()?;
        if let Some(p) = pads.iter().filter(|p| p.date.as_deref() == Some(key)).max_by(|a, b| a.updated_at.cmp(&b.updated_at)) {
            return Ok(p.clone());
        }
        let pad = carry(&rollover_sources(key, &pads), Pad::new_dated(key, Utc::now()));
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
        if rel.is_empty() || rel.contains('/') || rel.contains('\\') || rel.contains("..") { return None; }
        Some(self.root.join("assets").join(rel))
    }

    /// All sheets (or those carrying `tag`) plus the assets they reference, as one archive.
    pub fn archive(&self, tag: Option<&str>) -> Result<Archive> {
        let sheets: Vec<Pad> = self.list()?.into_iter().filter(|p| tag.map(|t| p.tags.iter().any(|x| x == t)).unwrap_or(true)).collect();
        let mut assets = BTreeMap::new();
        for b in sheets.iter().flat_map(|p| p.blocks.iter()) {
            if let Some(rel) = b.asset.as_deref() {
                if let Some(path) = self.asset_path(rel) {
                    if let Ok(bytes) = fs::read(&path) {
                        assets.insert(rel.to_string(), base64::engine::general_purpose::STANDARD.encode(bytes));
                    }
                }
            }
        }
        Ok(Archive { format: "scratchpad-archive".into(), v: 1, exported_at: Utc::now(), sheets, assets })
    }

    /// Merge an archive: sheets with an existing id are overwritten, assets are written when missing.
    pub fn import_archive(&self, archive: Archive) -> Result<ImportSummary> {
        if archive.format != "scratchpad-archive" { return Err(StoreError::BadArchive); }
        let mut summary = ImportSummary::default();
        for (rel, data) in archive.assets {
            let Some(path) = self.asset_path(&rel) else { continue };
            if path.exists() { continue; }
            let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(data) else { continue };
            fs::write(path, bytes)?;
            summary.assets += 1;
        }
        for sheet in archive.sheets {
            if !valid_id(&sheet.id) { continue; }
            self.save(&sheet)?;
            summary.sheets += 1;
        }
        Ok(summary)
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

pub fn parse_day(key: &str) -> Option<NaiveDate> { NaiveDate::parse_from_str(key, "%Y-%m-%d").ok() }

#[cfg(test)]
mod tests {
    use super::*;

    fn todo(text: &str, status: TodoStatus) -> Todo {
        Todo { id: text.to_string(), text: text.to_string(), status, created_at: Utc::now(), carried_from: None }
    }
    fn sample(name: &str) -> Vec<u8> {
        fs::read(Path::new(env!("CARGO_MANIFEST_DIR")).join("../../shared/samples").join(name)).unwrap()
    }

    #[test]
    fn ids_have_date_and_suffix() {
        let id = new_sheet_id("2026-10-12");
        assert!(id.starts_with("2026-10-12-") && id.len() == 17 && valid_id(&id));
        assert_ne!(new_sheet_id("2026-10-12"), id);
    }

    #[test]
    fn migrates_v1_sample() {
        let pad: Pad = serde_json::from_slice::<Pad>(&sample("pad-v1.json")).unwrap().migrate();
        assert_eq!(pad.v, 2);
        assert_eq!(pad.tags, vec!["work".to_string()]);
        let json = serde_json::to_value(&pad).unwrap();
        assert!(json.get("tag").is_none());
        assert_eq!(json["tags"][0], "work");
    }

    #[test]
    fn round_trips_v2_sample() {
        let pad: Pad = serde_json::from_slice::<Pad>(&sample("sheet-v2.json")).unwrap().migrate();
        assert_eq!(pad.tags, vec!["work".to_string(), "q4".to_string()]);
        assert_eq!(pad.blocks[1].col_widths, Some(vec![220, 104, 104]));
        assert_eq!(pad.blocks[4].font.as_deref(), Some("hand"));
        assert_eq!(pad.blocks[2].rotation, -3.0);
        let again: Pad = serde_json::from_str::<Pad>(&serde_json::to_string(&pad).unwrap()).unwrap().migrate();
        assert_eq!(again, pad);
    }

    #[test]
    fn carries_from_every_sheet_of_latest_day() {
        let mut a = Pad::new_dated("2026-10-11", Utc::now());
        a.todos = vec![todo("a", TodoStatus::Open), todo("b", TodoStatus::Done)];
        let mut b = Pad::new_dated("2026-10-11", Utc::now());
        b.todos = vec![todo("c", TodoStatus::Deferred), todo("  ", TodoStatus::Open)];
        let mut old = Pad::new_dated("2026-10-09", Utc::now());
        old.todos = vec![todo("old", TodoStatus::Open)];
        let pads = vec![a.clone(), b.clone(), old];
        let sources = rollover_sources("2026-10-12", &pads);
        assert_eq!(sources.len(), 2);
        let next = carry(&sources, Pad::new_dated("2026-10-12", Utc::now()));
        let mut texts: Vec<_> = next.todos.iter().map(|t| t.text.as_str()).collect();
        texts.sort();
        assert_eq!(texts, vec!["a", "c"]);
        assert!(next.todos.iter().all(|t| t.status == TodoStatus::Open));
    }

    #[test]
    fn today_reuses_existing_sheet_and_supports_several_per_day() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(dir.path()).unwrap();
        let mut prev = Pad::new_dated("2000-01-01", Utc::now());
        prev.todos = vec![todo("carry me", TodoStatus::Open)];
        store.save(&prev).unwrap();
        let first = store.today_for("2000-01-02").unwrap();
        assert_eq!(first.todos[0].text, "carry me");
        assert_eq!(store.today_for("2000-01-02").unwrap().id, first.id);
        store.save(&Pad::new_dated("2000-01-02", Utc::now())).unwrap();
        assert_eq!(store.list().unwrap().iter().filter(|p| p.date.as_deref() == Some("2000-01-02")).count(), 2);
        assert!(store.load("../etc/passwd").is_err());
    }

    #[test]
    fn archive_round_trip() {
        let a = tempfile::tempdir().unwrap();
        let src = Store::open(a.path()).unwrap();
        let rel = src.store_asset(b"png-bytes", "png").unwrap();
        let mut pad = Pad::new_dated("2026-10-12", Utc::now());
        pad.tags = vec!["work".into()];
        pad.blocks.push(Block { id: "i".into(), kind: BlockKind::Image, x: 0, y: 0, w: 96, h: None, text: None, rows: None,
            asset: Some(rel.clone()), name: None, size: None, url: None, caption: None, language: None,
            rotation: 0.0, font: None, font_size: None, bold: false, italic: false, col_widths: None });
        src.save(&pad).unwrap();
        src.save(&Pad::new_dated("2026-10-11", Utc::now())).unwrap();
        assert_eq!(src.archive(Some("work")).unwrap().sheets.len(), 1);
        let archive = src.archive(None).unwrap();
        assert_eq!(archive.sheets.len(), 2);
        let json = serde_json::to_vec(&archive).unwrap();

        let b = tempfile::tempdir().unwrap();
        let dst = Store::open(b.path()).unwrap();
        let summary = dst.import_archive(serde_json::from_slice(&json).unwrap()).unwrap();
        assert_eq!(summary, ImportSummary { sheets: 2, assets: 1 });
        assert_eq!(fs::read(dst.asset_path(&rel).unwrap()).unwrap(), b"png-bytes");
        assert!(dst.import_archive(Archive { format: "nope".into(), v: 1, exported_at: Utc::now(), sheets: vec![], assets: BTreeMap::new() }).is_err());
    }

    #[test]
    fn tags_normalise() {
        assert_eq!(normalize_tag(" #Q4 Plans"), "q4plans");
        let mut p = Pad::new_dated("2026-10-12", Utc::now());
        p.tag = Some("Work".into());
        p.tags = vec!["work".into(), "#home".into()];
        assert_eq!(p.migrate().tags, vec!["work".to_string(), "home".to_string()]);
    }

    #[test]
    fn title_parse_and_asset_paths() {
        assert_eq!(html_title("<html><head><TITLE>  Tauri &amp;\n  friends </title>"), Some("Tauri & friends".into()));
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(dir.path()).unwrap();
        let rel = store.store_asset(b"x", "png").unwrap();
        assert!(store.asset_path(&rel).unwrap().exists());
        assert!(store.asset_path("assets/../pads/x.json").is_none());
        assert!(store.asset_path("pads/x.json").is_none());
    }
}
