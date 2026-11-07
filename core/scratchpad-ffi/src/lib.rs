//! The boundary between scratchpad-core and Swift. Sheets are plain records, with no JSON hop.
//! Calls are small and synchronous, so nothing here is async and there's nothing to cancel.
//! Kinds, fonts and statuses cross as the strings the file uses, which Swift's enums already are.
use scratchpad_core::archive::Archive;
use scratchpad_core::dates::{self, Date};
use scratchpad_core::formula::{self, CellValue, TableEvaluator};
use scratchpad_core::model::{Block, BlockFont, BlockKind, Extras, Pad, Todo, TodoStatus};
use scratchpad_core::paste::{self, ClipboardContents, PasteResult};
use scratchpad_core::sidebar::{self, SheetGroup, TagSort};
use scratchpad_core::sort::{sorted_indices, TodoSortMode};
use scratchpad_core::store::{PadStore, StoreError};
use scratchpad_core::vault::{self, EntryState};
use scratchpad_core::export;
use std::sync::Arc;

uniffi::setup_scaffolding!();

// MARK: Sheets

#[derive(uniffi::Record, Clone)]
pub struct BlockRecord {
    pub id: String,
    pub kind: String,
    pub x: i64,
    pub y: i64,
    pub w: i64,
    pub h: Option<i64>,
    pub text: Option<String>,
    pub rows: Option<Vec<Vec<String>>>,
    pub asset: Option<String>,
    pub name: Option<String>,
    pub size: Option<i64>,
    pub url: Option<String>,
    pub caption: Option<String>,
    pub language: Option<String>,
    pub rotation: f64,
    pub font: String,
    pub font_size: i64,
    pub bold: bool,
    pub italic: bool,
    pub col_widths: Option<Vec<i64>>,
    /// Fields this build doesn't know, as a JSON object. Empty when there are none.
    pub extras: String,
}

#[derive(uniffi::Record, Clone)]
pub struct TodoRecord {
    pub id: String,
    pub text: String,
    pub status: String,
    pub created_at_ms: i64,
    pub carried_from: Option<String>,
    pub extras: String,
}

#[derive(uniffi::Record, Clone)]
pub struct PadRecord {
    pub id: String,
    pub date: Option<String>,
    pub title: String,
    pub tags: Vec<String>,
    pub pinned: bool,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub blocks: Vec<BlockRecord>,
    pub todos: Vec<TodoRecord>,
    pub extras: String,
}

fn extras_out(e: &Extras) -> String {
    if e.is_empty() { String::new() } else { serde_json::to_string(e).unwrap_or_default() }
}

fn extras_in(s: &str) -> Extras {
    if s.is_empty() { Extras::new() } else { serde_json::from_str(s).unwrap_or_default() }
}

impl From<&Block> for BlockRecord {
    fn from(b: &Block) -> BlockRecord {
        BlockRecord {
            id: b.id.clone(), kind: b.kind.name().into(), x: b.x, y: b.y, w: b.w, h: b.h, text: b.text.clone(), rows: b.rows.clone(),
            asset: b.asset.clone(), name: b.name.clone(), size: b.size, url: b.url.clone(), caption: b.caption.clone(),
            language: b.language.clone(), rotation: b.rotation, font: b.font.name().into(), font_size: b.font_size,
            bold: b.bold, italic: b.italic, col_widths: b.col_widths.clone(), extras: extras_out(&b.extra),
        }
    }
}

impl From<&BlockRecord> for Block {
    fn from(b: &BlockRecord) -> Block {
        Block {
            id: b.id.clone(), kind: BlockKind::from_name(&b.kind).unwrap_or(BlockKind::Text), x: b.x, y: b.y, w: b.w, h: b.h,
            text: b.text.clone(), rows: b.rows.clone(), asset: b.asset.clone(), name: b.name.clone(), size: b.size, url: b.url.clone(),
            caption: b.caption.clone(), language: b.language.clone(), rotation: b.rotation, font: BlockFont::from_name(&b.font),
            font_size: b.font_size, bold: b.bold, italic: b.italic, col_widths: b.col_widths.clone(), extra: extras_in(&b.extras),
        }
    }
}

impl From<&Todo> for TodoRecord {
    fn from(t: &Todo) -> TodoRecord {
        TodoRecord { id: t.id.clone(), text: t.text.clone(), status: t.status.name().into(), created_at_ms: t.created_at.0,
                     carried_from: t.carried_from.clone(), extras: extras_out(&t.extra) }
    }
}

impl From<&TodoRecord> for Todo {
    fn from(t: &TodoRecord) -> Todo {
        Todo { id: t.id.clone(), text: t.text.clone(), status: TodoStatus::from_name(&t.status).unwrap_or(TodoStatus::Open),
               created_at: Date(t.created_at_ms), carried_from: t.carried_from.clone(), extra: extras_in(&t.extras) }
    }
}

impl From<&Pad> for PadRecord {
    fn from(p: &Pad) -> PadRecord {
        PadRecord { id: p.id.clone(), date: p.date.clone(), title: p.title.clone(), tags: p.tags.clone(), pinned: p.pinned,
                    created_at_ms: p.created_at.0, updated_at_ms: p.updated_at.0, blocks: p.blocks.iter().map(Into::into).collect(),
                    todos: p.todos.iter().map(Into::into).collect(), extras: extras_out(&p.extra) }
    }
}

impl From<&PadRecord> for Pad {
    fn from(p: &PadRecord) -> Pad {
        Pad { id: p.id.clone(), date: p.date.clone(), title: p.title.clone(), tags: p.tags.clone(), pinned: p.pinned,
              created_at: Date(p.created_at_ms), updated_at: Date(p.updated_at_ms), blocks: p.blocks.iter().map(Into::into).collect(),
              todos: p.todos.iter().map(Into::into).collect(), extra: extras_in(&p.extras) }
    }
}

fn pads(records: &[PadRecord]) -> Vec<Pad> { records.iter().map(Into::into).collect() }

// MARK: Formulas, dates, paste

#[derive(uniffi::Enum, Clone, Debug, PartialEq)]
pub enum CellRecord {
    Empty,
    Number { value: f64 },
    Text { value: String },
    Error { code: String },
}

/// Every cell of a table, the same shape as `rows`.
#[uniffi::export]
pub fn evaluate_table(rows: Vec<Vec<String>>) -> Vec<Vec<CellRecord>> {
    let mut eval = TableEvaluator::new(&rows);
    eval.evaluate_all().into_iter().map(|row| row.into_iter().map(|v| match v {
        CellValue::Empty => CellRecord::Empty,
        CellValue::Number(value) => CellRecord::Number { value },
        CellValue::Text(value) => CellRecord::Text { value },
        CellValue::Error(e) => CellRecord::Error { code: e.text().to_string() },
    }).collect()).collect()
}

#[uniffi::export]
pub fn format_number(value: f64) -> String { formula::format_number(value) }

#[uniffi::export]
pub fn parse_number(raw: String) -> Option<f64> { formula::parse_number(&raw) }

#[uniffi::export]
pub fn parse_day_phrase(input: String, today: String) -> Option<String> { dates::parse_phrase(&input, &today) }

#[derive(uniffi::Enum, Clone, Debug, PartialEq)]
pub enum PasteRecord {
    Text { text: String },
    Code { body: String, language: Option<String> },
    Link { url: String, title: Option<String> },
    Table { rows: Vec<Vec<String>> },
}

/// What text on a clipboard becomes. Files and images are the shell's: it read them, and they're
/// never worth carrying across here.
#[uniffi::export]
pub fn classify_paste(plain: Option<String>, html: Option<String>) -> Vec<PasteRecord> {
    let clip = ClipboardContents { plain, html, ..Default::default() };
    paste::classify(&clip, &|_| None).into_iter().filter_map(|r| match r {
        PasteResult::Text(text) => Some(PasteRecord::Text { text }),
        PasteResult::Code(body, language) => Some(PasteRecord::Code { body, language }),
        PasteResult::Link(url, title) => Some(PasteRecord::Link { url, title }),
        PasteResult::Table(rows) => Some(PasteRecord::Table { rows }),
        PasteResult::Image(..) | PasteResult::File(_) => None,
    }).collect()
}

#[uniffi::export]
pub fn html_title(html: String) -> Option<String> { paste::html_title(&html) }

// MARK: Sorting and the sidebar: positions cross, not sheets

/// The view order, as positions in `todos`.
#[uniffi::export]
pub fn sort_todos(todos: Vec<TodoRecord>, mode: String, done_sinks: bool, now_ms: i64) -> Vec<u32> {
    let rows: Vec<Todo> = todos.iter().map(Into::into).collect();
    sorted_indices(&rows, TodoSortMode::from_name(&mode), done_sinks, Date(now_ms)).into_iter().map(|i| i as u32).collect()
}

/// What the sidebar needs of a sheet.
#[derive(uniffi::Record, Clone)]
pub struct SheetRow {
    pub id: String,
    pub date: Option<String>,
    pub title: String,
    pub tags: Vec<String>,
    pub pinned: bool,
    pub updated_at_ms: i64,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct GroupRecord {
    pub id: String,
    pub label: String,
    pub detail: String,
    /// Positions in the rows given.
    pub sheets: Vec<u32>,
}

fn light(rows: &[SheetRow]) -> Vec<Pad> {
    rows.iter().map(|r| {
        let at = Date(r.updated_at_ms);
        let mut p = Pad::new(r.id.clone(), r.date.clone(), r.title.clone(), &[], r.pinned, at);
        p.tags = r.tags.clone();
        p
    }).collect()
}

fn position(list: &[Pad], p: &Pad) -> u32 {
    ((p as *const Pad as usize - list.as_ptr() as usize) / std::mem::size_of::<Pad>()) as u32
}

fn groups(list: &[Pad], found: Vec<SheetGroup<'_>>) -> Vec<GroupRecord> {
    found.into_iter().map(|g| GroupRecord {
        sheets: g.sheets.iter().map(|p| position(list, p)).collect(), id: g.id, label: g.label, detail: g.detail,
    }).collect()
}

/// `mode` is `byDay`, `byMonth`, `recent` or `byTag`; `tag_sort` applies to the last.
#[uniffi::export]
pub fn sidebar_groups(rows: Vec<SheetRow>, mode: String, tag_sort: String, today: String) -> Vec<GroupRecord> {
    let list = light(&rows);
    let found = match mode.as_str() {
        "byMonth" => sidebar::by_month(&list),
        "recent" => sidebar::recent(&list),
        "byTag" => sidebar::by_tag(&list, match tag_sort.as_str() {
            "mostSheets" => TagSort::MostSheets,
            "recentlyUsed" => TagSort::RecentlyUsed,
            _ => TagSort::Alphabetical,
        }),
        _ => sidebar::by_day(&list, &today),
    };
    groups(&list, found)
}

// MARK: Exports

#[uniffi::export]
pub fn export_sheet(pad: PadRecord) -> String { export::sheet(&(&pad).into()) }

#[uniffi::export]
pub fn export_everything(sheets: Vec<PadRecord>) -> String { export::everything(&pads(&sheets)) }

#[uniffi::export]
pub fn export_todos(sheets: Vec<PadRecord>, include_done: bool, include_deferred: bool, open_only: bool) -> String {
    export::todos(&pads(&sheets), include_done, include_deferred, open_only)
}

#[uniffi::export]
pub fn export_table(rows: Vec<Vec<String>>) -> String { export::table(&rows) }

#[uniffi::export]
pub fn export_json(sheets: Vec<PadRecord>) -> Vec<u8> { export::sheets_json(&pads(&sheets)) }

// MARK: The store

#[derive(Debug, uniffi::Error)]
pub enum VaultFailure {
    Failed { message: String },
}

impl std::fmt::Display for VaultFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let VaultFailure::Failed { message } = self;
        f.write_str(message)
    }
}

impl std::error::Error for VaultFailure {}

impl From<uniffi::UnexpectedUniFFICallbackError> for VaultFailure {
    fn from(e: uniffi::UnexpectedUniFFICallbackError) -> VaultFailure { VaultFailure::Failed { message: e.reason } }
}

#[derive(uniffi::Record, Clone)]
pub struct VaultItem {
    /// Relative to the vault, under its real name even if it isn't here yet.
    pub path: String,
    pub modified: Option<f64>,
    pub downloaded: bool,
}

/// Files, in the shell's hands. On Apple: plain reads, coordinated writes, placeholders.
#[uniffi::export(with_foreign)]
pub trait Vault: Send + Sync {
    fn list(&self, dir: String) -> Result<Vec<VaultItem>, VaultFailure>;
    fn read(&self, path: String) -> Result<Vec<u8>, VaultFailure>;
    fn write(&self, path: String, data: Vec<u8>) -> Result<(), VaultFailure>;
    fn remove(&self, path: String) -> Result<(), VaultFailure>;
    fn exists(&self, path: String) -> bool;
    fn local_url(&self, path: String) -> Option<String>;
}

struct Bridge(Arc<dyn Vault>);

fn lost(e: VaultFailure) -> vault::VaultError { vault::VaultError(e.to_string()) }

impl vault::Vault for Bridge {
    fn list(&self, dir: &str) -> Result<Vec<vault::VaultEntry>, vault::VaultError> {
        Ok(self.0.list(dir.to_string()).map_err(lost)?.into_iter().map(|i| vault::VaultEntry {
            path: i.path, modified: i.modified,
            state: if i.downloaded { EntryState::Available } else { EntryState::NotDownloaded },
        }).collect())
    }
    fn read(&self, path: &str) -> Result<Vec<u8>, vault::VaultError> { self.0.read(path.to_string()).map_err(lost) }
    fn write(&self, path: &str, data: &[u8]) -> Result<(), vault::VaultError> { self.0.write(path.to_string(), data.to_vec()).map_err(lost) }
    fn remove(&self, path: &str) -> Result<(), vault::VaultError> { self.0.remove(path.to_string()).map_err(lost) }
    fn exists(&self, path: &str) -> bool { self.0.exists(path.to_string()) }
    fn local_url(&self, path: &str) -> Option<String> { self.0.local_url(path.to_string()) }
}

#[derive(Debug, uniffi::Error)]
pub enum LibraryError {
    /// Sheets are on their way, so what's here isn't the whole picture yet.
    StillDownloading,
    InvalidId { id: String },
    Failed { message: String },
}

impl std::fmt::Display for LibraryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LibraryError::StillDownloading => f.write_str("Your sheets are still downloading from iCloud."),
            LibraryError::InvalidId { id } => write!(f, "Not a valid sheet id: {id}"),
            LibraryError::Failed { message } => f.write_str(message),
        }
    }
}

impl std::error::Error for LibraryError {}

impl From<StoreError> for LibraryError {
    fn from(e: StoreError) -> LibraryError {
        match e {
            StoreError::StillDownloading => LibraryError::StillDownloading,
            StoreError::InvalidId(id) => LibraryError::InvalidId { id },
            other => LibraryError::Failed { message: other.to_string() },
        }
    }
}

#[derive(uniffi::Record)]
pub struct ListRecord {
    pub sheets: Vec<PadRecord>,
    pub unreadable: Vec<String>,
    pub pending: Vec<String>,
}

#[derive(uniffi::Record)]
pub struct ImportRecord {
    pub sheets: u32,
    pub overwritten: u32,
    pub assets_written: u32,
    pub skipped: u32,
    pub kept_newer: u32,
}

/// One store. The host passes `now` and the local day key, so no clock crosses.
#[derive(uniffi::Object)]
pub struct PadLibrary { store: PadStore<Bridge> }

#[uniffi::export]
impl PadLibrary {
    #[uniffi::constructor]
    pub fn open(vault: Arc<dyn Vault>) -> Arc<PadLibrary> { Arc::new(PadLibrary { store: PadStore::new(Bridge(vault)) }) }

    pub fn scan(&self) -> Result<ListRecord, LibraryError> {
        let found = self.store.scan()?;
        Ok(ListRecord { sheets: found.sheets.iter().map(Into::into).collect(), unreadable: found.unreadable, pending: found.pending })
    }

    pub fn load(&self, id: String) -> Result<Option<PadRecord>, LibraryError> {
        Ok(self.store.load(&id)?.as_ref().map(Into::into))
    }

    /// `touch_ms` stamps updatedAt. Leave it out for imports, which keep their times.
    pub fn save(&self, pad: PadRecord, touch_ms: Option<i64>) -> Result<PadRecord, LibraryError> {
        Ok((&self.store.save(&(&pad).into(), touch_ms.map(Date))?).into())
    }

    pub fn delete(&self, id: String) -> Result<(), LibraryError> { Ok(self.store.delete(&id)?) }

    pub fn today(&self, now_ms: i64, today_key: String, ignoring_downloads: bool) -> Result<PadRecord, LibraryError> {
        Ok((&self.store.today(Date(now_ms), &today_key, ignoring_downloads)?).into())
    }

    pub fn create(&self, date: String, tags: Vec<String>, title: String, now_ms: i64, today_key: String) -> Result<PadRecord, LibraryError> {
        Ok((&self.store.create(&date, &tags, &title, Date(now_ms), &today_key)?).into())
    }

    pub fn create_pinned(&self, title: String, tags: Vec<String>, now_ms: i64) -> Result<PadRecord, LibraryError> {
        Ok((&self.store.create_pinned(&title, &tags, Date(now_ms))?).into())
    }

    pub fn duplicate(&self, pad: PadRecord, now_ms: i64) -> Result<PadRecord, LibraryError> {
        Ok((&self.store.duplicate(&(&pad).into(), Date(now_ms))?).into())
    }

    pub fn move_to(&self, pad: PadRecord, day: String, now_ms: i64) -> Result<PadRecord, LibraryError> {
        Ok((&self.store.move_to(&(&pad).into(), &day, Date(now_ms))?).into())
    }

    pub fn store_asset(&self, data: Vec<u8>, ext: String) -> Result<String, LibraryError> {
        Ok(self.store.store_asset(&data, &ext)?)
    }

    /// A `.scratchpad` archive of these sheets and the assets they show.
    pub fn archive(&self, sheets: Vec<PadRecord>, now_ms: i64) -> Vec<u8> {
        Archive::build(&pads(&sheets), &self.store, Date(now_ms)).encoded()
    }

    pub fn import_archive(&self, data: Vec<u8>) -> Result<ImportRecord, LibraryError> {
        let archive = Archive::decode(&data).ok_or(LibraryError::Failed { message: "This file is not a Scratchpad archive.".into() })?;
        let r = archive.import_into(&self.store)?;
        Ok(ImportRecord { sheets: r.sheets as u32, overwritten: r.overwritten as u32, assets_written: r.assets_written as u32,
                          skipped: r.skipped as u32, kept_newer: r.kept_newer as u32 })
    }
}
