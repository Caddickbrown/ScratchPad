//! The store over a Vault: <root>/pads/<id>.json and <root>/assets/<uuid>.<ext>.
//! Reading never writes. A file that won't parse is reported by name, and nothing here
//! deletes or overwrites it.
use crate::dates::Date;
use crate::json::encode_pad;
use crate::model::*;
use crate::rollover;
use crate::vault::{EntryState, Vault, VaultError};
use std::cmp::Ordering;
use std::collections::HashSet;

#[derive(Debug)]
pub enum StoreError {
    Vault(VaultError),
    InvalidId(String),
    Json(serde_json::Error),
    /// Sheets are on their way, so what's here isn't the whole picture yet.
    StillDownloading,
}

impl From<VaultError> for StoreError { fn from(e: VaultError) -> StoreError { StoreError::Vault(e) } }
impl From<serde_json::Error> for StoreError { fn from(e: serde_json::Error) -> StoreError { StoreError::Json(e) } }

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StoreError::Vault(e) => write!(f, "{e}"),
            StoreError::InvalidId(id) => write!(f, "Not a valid sheet id: {id}"),
            StoreError::Json(e) => write!(f, "{e}"),
            StoreError::StillDownloading => f.write_str("Your sheets are still downloading from iCloud."),
        }
    }
}

impl std::error::Error for StoreError {}

pub type Result<T> = std::result::Result<T, StoreError>;

/// What's in the store, including what can't be shown.
#[derive(Default, Debug, Clone)]
pub struct ListResult {
    pub sheets: Vec<Pad>,
    /// File names that are there but aren't sheets this app can read.
    pub unreadable: Vec<String>,
    /// Ids of sheets that haven't been downloaded yet.
    pub pending: Vec<String>,
}

impl ListResult {
    /// Ids that hold a file nobody can compare with: it won't read, or it isn't here yet.
    pub fn uncertain_ids(&self) -> HashSet<String> {
        self.pending.iter().cloned()
            .chain(self.unreadable.iter().map(|n| n.trim_end_matches(".json").to_string()))
            .collect()
    }

    /// Every id with a file behind it. A sheet that won't read or hasn't arrived still holds
    /// its name, so a new sheet can't be written over it.
    pub fn taken_ids(&self) -> HashSet<String> {
        let mut ids = self.uncertain_ids();
        ids.extend(self.sheets.iter().map(|p| p.id.clone()));
        ids
    }
}

/// Dated sheets by date descending, pinned after, ties by updatedAt descending.
pub fn newest_first(a: &Pad, b: &Pad) -> Ordering {
    let (da, db) = (a.date.as_deref().unwrap_or(""), b.date.as_deref().unwrap_or(""));
    db.cmp(da).then_with(|| b.updated_at.cmp(&a.updated_at)).then_with(|| a.id.cmp(&b.id))
}

pub struct PadStore<V: Vault> { pub vault: V }

impl<V: Vault> PadStore<V> {
    pub fn new(vault: V) -> PadStore<V> { PadStore { vault } }

    fn path(id: &str) -> String { format!("pads/{}.json", id) }

    pub fn scan(&self) -> Result<ListResult> {
        let mut out = ListResult::default();
        for e in self.vault.list("pads")? {
            let Some(name) = e.path.strip_prefix("pads/") else { continue };
            if !name.ends_with(".json") || name.starts_with('.') { continue; }
            if e.state == EntryState::NotDownloaded {
                out.pending.push(name.trim_end_matches(".json").to_string());
                continue;
            }
            match self.vault.read(&e.path).ok().and_then(|b| Pad::from_json(&b).ok()) {
                Some(p) => out.sheets.push(p),
                None => out.unreadable.push(name.to_string()),
            }
        }
        out.sheets.sort_by(newest_first);
        out.unreadable.sort();
        out.pending.sort();
        Ok(out)
    }

    pub fn list(&self) -> Result<Vec<Pad>> { Ok(self.scan()?.sheets) }

    pub fn load(&self, id: &str) -> Result<Option<Pad>> {
        if !is_valid_id(id) { return Ok(None); }
        let path = Self::path(id);
        if !self.vault.exists(&path) { return Ok(None); }
        Ok(Some(Pad::from_json(&self.vault.read(&path)?)?))
    }

    /// Writes v2 JSON. `touch` stamps updatedAt (none for imports, which keep their times).
    /// Empty to-do rows are dropped.
    pub fn save(&self, pad: &Pad, touch: Option<Date>) -> Result<Pad> {
        if !is_valid_id(&pad.id) { return Err(StoreError::InvalidId(pad.id.clone())); }
        let mut p = pad.compacted();
        if let Some(now) = touch { p.updated_at = now; }
        self.vault.write(&Self::path(&p.id), &encode_pad(&p))?;
        Ok(p)
    }

    pub fn delete(&self, id: &str) -> Result<()> {
        if !is_valid_id(id) { return Err(StoreError::InvalidId(id.to_string())); }
        Ok(self.vault.remove(&Self::path(id))?)
    }

    /// Today's sheet, most recently updated when there are several, or a new one with carry-over.
    /// While sheets are downloading it refuses to make one: today's may be among them, and carrying
    /// over from a partial list would carry to-dos twice. `ignoring_downloads` is for a device that
    /// has waited and can't reach them: it gets a sheet with nothing carried, for the same reason.
    /// `today_key` comes from the host, which owns the timezone.
    pub fn today(&self, now: Date, today_key: &str, ignoring_downloads: bool) -> Result<Pad> {
        let scan = self.scan()?;
        if let Some(existing) = scan.sheets.iter().filter(|p| p.date.as_deref() == Some(today_key)).max_by_key(|p| p.updated_at) {
            return Ok(existing.clone());
        }
        if !scan.pending.is_empty() && !ignoring_downloads { return Err(StoreError::StillDownloading); }
        self.create_among(today_key, &[], "", now, today_key, &scan)
    }

    pub fn create(&self, date: &str, tags: &[String], title: &str, now: Date, today_key: &str) -> Result<Pad> {
        let scan = self.scan()?;
        self.create_among(date, tags, title, now, today_key, &scan)
    }

    fn create_among(&self, date: &str, tags: &[String], title: &str, now: Date, today_key: &str, scan: &ListResult) -> Result<Pad> {
        let mut pad = Pad::new(make_sheet_id(date), Some(date.to_string()), title.to_string(), tags, false, now);
        let taken = scan.taken_ids();
        while taken.contains(&pad.id) { pad.id = make_sheet_id(date); }
        if date == today_key && scan.pending.is_empty() && !scan.sheets.iter().any(|p| p.date.as_deref() == Some(today_key)) {
            pad = rollover::carried(&rollover::sources(today_key, &scan.sheets), pad);
        }
        self.save(&pad, None)
    }

    pub fn create_pinned(&self, title: &str, tags: &[String], now: Date) -> Result<Pad> {
        let taken = self.scan()?.taken_ids();
        let pad = Pad::new(slug(title, &taken), None, title.to_string(), tags, true, now);
        self.save(&pad, None)
    }

    pub fn duplicate(&self, pad: &Pad, now: Date) -> Result<Pad> {
        let taken = self.scan()?.taken_ids();
        let new_id = match &pad.date {
            Some(d) => {
                let mut id = make_sheet_id(d);
                while taken.contains(&id) { id = make_sheet_id(d); }
                id
            }
            None => slug(&format!("{} copy", pad.title), &taken),
        };
        self.save(&pad.duplicate(new_id, now, &mut new_uuid), None)
    }

    /// The id stays put: it is the file name, and other sheets' carriedFrom points at it.
    pub fn move_to(&self, pad: &Pad, day: &str, now: Date) -> Result<Pad> {
        if pad.date.as_deref() == Some(day) && !pad.pinned { return Ok(pad.clone()); }
        self.save(&pad.moved(day), Some(now))
    }

    /// Writes bytes into assets/ and returns the store-relative path to put in a block.
    pub fn store_asset(&self, data: &[u8], ext: &str) -> Result<String> {
        let ext: String = ext.chars().filter(char::is_ascii_alphanumeric).take(8).collect::<String>().to_lowercase();
        let name = format!("assets/{}.{}", new_uuid().to_lowercase(), if ext.is_empty() { "bin" } else { &ext });
        self.vault.write(&name, data)?;
        Ok(name)
    }
}
