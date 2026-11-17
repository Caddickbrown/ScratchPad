//! The store on throwaway folders: the safety rules first. iCloud placeholders are a test vault.
use scratchpad_core::archive::Archive;
use scratchpad_core::dates::Date;
use scratchpad_core::model::*;
use scratchpad_core::rollover::{resume_step, resume_step_with, ResumeStep};
use scratchpad_core::store::{PadStore, StoreError};
use scratchpad_core::vault::{EntryState, FsVault, Vault, VaultEntry, VaultError};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::sync::Arc;

const NOW: Date = Date(1_794_000_000_000);
const TODAY: &str = "2026-11-05";
const YESTERDAY: &str = "2026-11-04";

fn store(dir: &Path) -> PadStore<FsVault> { PadStore::new(FsVault::open(dir).unwrap()) }

/// FsVault that says some sheets aren't downloaded, as AppleVault does.
struct Evicted { inner: FsVault, away: Vec<String> }

impl Vault for Evicted {
    fn list(&self, dir: &str) -> Result<Vec<VaultEntry>, VaultError> {
        let mut out = self.inner.list(dir)?;
        out.extend(self.away.iter().map(|id| VaultEntry { path: format!("{dir}/{id}.json"), modified: None, state: EntryState::NotDownloaded }));
        Ok(out)
    }
    fn read(&self, path: &str) -> Result<Vec<u8>, VaultError> { self.inner.read(path) }
    fn write(&self, path: &str, data: &[u8]) -> Result<(), VaultError> { self.inner.write(path, data) }
    fn remove(&self, path: &str) -> Result<(), VaultError> { self.inner.remove(path) }
    fn exists(&self, path: &str) -> bool { self.inner.exists(path) }
    fn local_url(&self, path: &str) -> Option<String> { self.inner.local_url(path) }
}

fn evicted(dir: &Path, away: &[&str]) -> PadStore<Evicted> {
    PadStore::new(Evicted { inner: FsVault::open(dir).unwrap(), away: away.iter().map(|s| s.to_string()).collect() })
}

fn yesterday_with_a_todo<V: Vault>(s: &PadStore<V>) {
    let mut pad = s.create(YESTERDAY, &[], "", NOW, TODAY).unwrap();
    pad.todos.push(Todo { id: "t".into(), text: "Ring the bank".into(), status: TodoStatus::Open, created_at: NOW, carried_from: None, extra: Extras::new() });
    s.save(&pad, None).unwrap();
}

fn hash_tree(dir: &Path) -> BTreeMap<String, (Vec<u8>, std::time::SystemTime)> {
    let mut out = BTreeMap::new();
    for sub in ["pads", "assets"] {
        for e in fs::read_dir(dir.join(sub)).unwrap() {
            let p = e.unwrap().path();
            out.insert(p.to_string_lossy().into_owned(), (fs::read(&p).unwrap(), fs::metadata(&p).unwrap().modified().unwrap()));
        }
    }
    out
}

#[test]
fn reading_never_writes() {
    let dir = tempfile::tempdir().unwrap();
    let s = store(dir.path());
    fs::write(dir.path().join("pads/2020-01-01.json"), br#"{"v":1,"id":"2020-01-01","date":"2020-01-01","tag":"Work","createdAt":"2020-01-01T08:00:00.123456Z"}"#).unwrap();
    fs::write(dir.path().join("pads/broken.json"), b"{ not a sheet").unwrap();
    let before = hash_tree(dir.path());
    let found = s.scan().unwrap();
    s.load("2020-01-01").unwrap();
    assert_eq!(found.sheets[0].tags, ["work"]);
    assert_eq!(found.unreadable, ["broken.json"]);
    assert_eq!(hash_tree(dir.path()), before, "reading changed a file");
}

#[test]
fn a_new_sheet_never_lands_on_one_that_wont_read_or_hasnt_arrived() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("pads/plans.json");
    fs::create_dir_all(dir.path().join("pads")).unwrap();
    fs::write(&file, b"{ not a sheet").unwrap();
    let s = evicted(dir.path(), &["ideas"]);
    assert_eq!(s.create_pinned("Plans", &[], NOW).unwrap().id, "plans-2");
    assert_eq!(s.create_pinned("Ideas", &[], NOW).unwrap().id, "ideas-2");
    assert_eq!(fs::read(&file).unwrap(), b"{ not a sheet");
    let pinned = s.create_pinned("Soup", &[], NOW).unwrap();
    fs::write(dir.path().join("pads/soup-copy.json"), b"{ not a sheet").unwrap();
    assert_eq!(s.duplicate(&pinned, NOW).unwrap().id, "soup-copy-2");
}

#[test]
fn today_waits_for_downloads_and_never_carries_from_a_partial_list() {
    let dir = tempfile::tempdir().unwrap();
    let s = evicted(dir.path(), &["2026-11-05-abcdef"]);
    yesterday_with_a_todo(&s);
    assert!(matches!(s.today(NOW, TODAY, false), Err(StoreError::StillDownloading)));
    assert_eq!(s.list().unwrap().len(), 1, "a second sheet was made");
    assert!(s.today(NOW, TODAY, true).unwrap().todos.is_empty(), "carried from a partial list");
    let other = tempfile::tempdir().unwrap();
    let s = evicted(other.path(), &["2026-11-05-abcdef"]);
    yesterday_with_a_todo(&s);
    assert!(s.create(TODAY, &[], "", NOW, TODAY).unwrap().todos.is_empty(), "carried from a partial list");
}

#[test]
fn today_finds_an_arrived_sheet_and_carries_when_nothing_is_away() {
    let dir = tempfile::tempdir().unwrap();
    let s = store(dir.path());
    yesterday_with_a_todo(&s);
    let today = s.today(NOW, TODAY, false).unwrap();
    assert_eq!(today.todos[0].text, "Ring the bank");
    assert_eq!(s.today(NOW, TODAY, false).unwrap().id, today.id);
    let e = evicted(dir.path(), &["2020-01-01-abcdef"]);
    assert_eq!(e.today(NOW, TODAY, false).unwrap().id, today.id);
}

#[test]
fn unknown_fields_survive_a_save_at_every_level() {
    let dir = tempfile::tempdir().unwrap();
    let s = store(dir.path());
    fs::write(dir.path().join("pads/a.json"), br#"{"id":"a","createdAt":"2026-01-02T03:04:05Z","mood":"good","zeta":{"b":[1,2.5,null],"a":{}},
        "blocks":[{"id":"b","kind":"text","x":0,"y":0,"w":96,"ink":"blue"}],
        "todos":[{"id":"t","text":"x","status":"open","createdAt":"2026-01-02T03:04:05Z","due":"2026-02-02"}]}"#).unwrap();
    let mut pad = s.load("a").unwrap().unwrap();
    pad.title = "Edited".into();
    s.save(&pad, Some(NOW)).unwrap();
    let again: serde_json::Value = serde_json::from_slice(&fs::read(dir.path().join("pads/a.json")).unwrap()).unwrap();
    assert_eq!(again["title"], "Edited");
    assert_eq!(again["mood"], "good");
    assert_eq!(again["zeta"]["b"][1], 2.5);
    assert_eq!(again["blocks"][0]["ink"], "blue");
    assert_eq!(again["todos"][0]["due"], "2026-02-02");
    let bytes = fs::read_to_string(dir.path().join("pads/a.json")).unwrap();
    let keys: Vec<&str> = bytes.lines().filter(|l| l.starts_with("  \"")).map(|l| l.trim().split('"').nth(1).unwrap()).collect();
    let mut order = keys.clone();
    order.sort();
    assert_eq!(keys, order, "keys must stay sorted");
}

fn sheet(id: &str, title: &str, at: Date) -> Pad {
    let mut p = Pad::new(id.into(), Some("2026-01-02".into()), title.into(), &[], false, at);
    p.updated_at = at;
    p
}

fn archive(sheets: Vec<Pad>) -> Archive { Archive { exported_at: NOW, sheets, assets: BTreeMap::new() } }

#[test]
fn importing_keeps_the_newer_sheet_and_each_sheets_own_times() {
    let dir = tempfile::tempdir().unwrap();
    let s = store(dir.path());
    s.save(&sheet("a", "Newer", NOW), None).unwrap();
    let r = archive(vec![sheet("a", "Old", NOW.plus_days(-1)), sheet("b", "New", NOW.plus_days(-9))]).import_into(&s).unwrap();
    assert_eq!((r.sheets, r.kept_newer, r.overwritten), (1, 1, 0));
    assert_eq!(s.load("a").unwrap().unwrap().title, "Newer");
    assert_eq!(s.load("b").unwrap().unwrap().updated_at, NOW.plus_days(-9));
    let r = archive(vec![sheet("a", "Newest", NOW.plus_days(1))]).import_into(&s).unwrap();
    assert_eq!((r.sheets, r.overwritten), (1, 1));
    assert_eq!(s.load("a").unwrap().unwrap().title, "Newest");
}

#[test]
fn importing_never_replaces_a_sheet_that_wont_read_or_hasnt_arrived() {
    let dir = tempfile::tempdir().unwrap();
    fs::create_dir_all(dir.path().join("pads")).unwrap();
    fs::write(dir.path().join("pads/bad.json"), b"{ not a sheet").unwrap();
    let s = evicted(dir.path(), &["away"]);
    let r = archive(vec![sheet("bad", "x", NOW), sheet("away", "x", NOW), sheet("../up", "x", NOW)]).import_into(&s).unwrap();
    assert_eq!((r.sheets, r.skipped), (0, 3));
    assert_eq!(fs::read(dir.path().join("pads/bad.json")).unwrap(), b"{ not a sheet");
    assert!(!dir.path().join("pads/away.json").exists());
}

#[test]
fn archives_round_trip_with_their_assets_and_refuse_unsafe_paths() {
    let (a, b) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
    let (src, dst) = (store(a.path()), store(b.path()));
    let rel = src.store_asset(b"png-bytes", "PNG").unwrap();
    assert!(rel.starts_with("assets/") && rel.ends_with(".png"), "{rel}");
    let mut pad = sheet("a", "With picture", NOW);
    let mut block = Block::new("i".into(), BlockKind::Image, 0, 0, 96);
    block.asset = Some(rel.clone());
    pad.blocks.push(block);
    src.save(&pad, None).unwrap();
    let mut archive = Archive::build(&src.list().unwrap(), &src, NOW);
    archive.assets.insert("assets/../../escape".into(), "eA==".into());
    archive.assets.insert("pads/x.json".into(), "eA==".into());
    let r = Archive::decode(&archive.encoded()).unwrap().import_into(&dst).unwrap();
    assert_eq!((r.sheets, r.assets_written, r.skipped), (1, 1, 2));
    assert_eq!(dst.vault.read(&rel).unwrap(), b"png-bytes");
    assert!(!b.path().parent().unwrap().join("escape").exists());
    assert!(Archive::decode(b"{\"format\":\"other\"}").is_none());
}

#[test]
fn the_vault_refuses_anything_outside_its_folder() {
    let dir = tempfile::tempdir().unwrap();
    let v = FsVault::open(dir.path().join("root")).unwrap();
    fs::write(dir.path().join("secret"), b"x").unwrap();
    for path in ["../secret", "pads/../../secret", "/etc/hosts"] {
        assert!(v.read(path).is_err(), "{path}");
        assert!(v.write(path, b"y").is_err(), "{path}");
        assert!(v.remove(path).is_err(), "{path}");
        assert!(!v.exists(path), "{path}");
    }
    assert_eq!(fs::read(dir.path().join("secret")).unwrap(), b"x");
}

#[test]
fn a_failed_write_leaves_the_old_sheet_and_no_stray_file() {
    let dir = tempfile::tempdir().unwrap();
    let s = store(dir.path());
    s.save(&sheet("a", "Kept", NOW), None).unwrap();
    assert!(s.save(&sheet("../a", "x", NOW), None).is_err());
    assert!(s.delete("../a").is_err());
    assert!(s.load("../a").unwrap().is_none());
    assert_eq!(s.load("a").unwrap().unwrap().title, "Kept");
    let names: Vec<_> = fs::read_dir(dir.path().join("pads")).unwrap().map(|e| e.unwrap().file_name()).collect();
    assert_eq!(names, ["a.json"]);
}

#[test]
fn many_writers_on_one_sheet_always_leave_a_whole_file() {
    let dir = tempfile::tempdir().unwrap();
    let s = Arc::new(store(dir.path()));
    let mut pad = sheet("a", "x", NOW);
    pad.blocks.push({ let mut b = Block::new("b".into(), BlockKind::Text, 0, 0, 96); b.text = Some("line ".repeat(2000)); b });
    s.save(&pad, None).unwrap();
    let writers: Vec<_> = (0..4).map(|i| {
        let (s, mut p) = (s.clone(), pad.clone());
        std::thread::spawn(move || for n in 0..25 { p.title = format!("{i}-{n}"); s.save(&p, None).unwrap(); })
    }).collect();
    for _ in 0..200 { assert!(s.load("a").unwrap().is_some(), "a reader saw part of a file"); }
    for w in writers { w.join().unwrap(); }
    assert_eq!(s.scan().unwrap().unreadable.len(), 0);
}

#[test]
fn ids_are_well_formed_and_differ() {
    let id = make_sheet_id("2026-10-12");
    assert!(is_dated_id(&id) && is_valid_id(&id), "{id}");
    let ids: std::collections::HashSet<String> = (0..2000).map(|_| make_sheet_id("2026-10-12")).collect();
    assert!(ids.len() >= 1999);
    assert_eq!(new_uuid().len(), 36);
    let uuid = new_uuid();
    assert_eq!(uuid, uuid.to_uppercase());
}

#[test]
fn coming_back() {
    let here = sheet("s", "", NOW);
    let newer = sheet("s", "", NOW.plus_days(1));
    assert_eq!(resume_step(Some(&here), Some(&here), "2026-01-02", "2026-01-02"), ResumeStep::Nothing);
    assert_eq!(resume_step(Some(&here), Some(&newer), "2026-01-02", "2026-01-02"), ResumeStep::Load(newer.clone()));
    assert_eq!(resume_step(Some(&newer), Some(&here), "2026-01-02", "2026-01-02"), ResumeStep::Nothing);
    assert_eq!(resume_step(Some(&here), Some(&here), "2026-01-02", "2026-01-03"), ResumeStep::OpenToday);
    assert_eq!(resume_step(Some(&here), Some(&here), "2026-02-02", "2026-02-03"), ResumeStep::Nothing);
    assert_eq!(resume_step(None, None, "2026-01-02", "2026-01-02"), ResumeStep::OpenToday);
}

/// "New sheet each day" off (the default since 17 Nov): a new day leaves the sheet open, and no sheet opens the latest.
#[test]
fn coming_back_without_a_daily_sheet() {
    let here = sheet("s", "", NOW);
    let newer = sheet("s", "", NOW.plus_days(1));
    assert_eq!(resume_step_with(Some(&here), Some(&here), "2026-01-02", "2026-01-03", false), ResumeStep::Nothing);
    assert_eq!(resume_step_with(Some(&here), Some(&newer), "2026-01-02", "2026-01-03", false), ResumeStep::Load(newer.clone()));
    assert_eq!(resume_step_with(None, None, "2026-01-02", "2026-01-02", false), ResumeStep::OpenLatest);
    assert_eq!(resume_step_with(Some(&here), Some(&here), "2026-01-02", "2026-01-03", true), ResumeStep::OpenToday);
}

/// Differences from Swift that stay, each out of reach of any real sheet. Pinned here so a change shows.
#[test]
fn known_differences() {
    // Foundation goes to the Julian calendar before 1582. The core stays Gregorian.
    assert_eq!(Date::parse("0001-01-01T00:00:00Z").unwrap().0, -62_135_596_800_000);
    // JSONDecoder reads a file with a duplicated key; the core calls it unreadable. No writer
    // makes one, and unreadable is the safe side: the file stays and is named.
    assert!(Pad::from_json(br#"{"id":"a","id":"b","createdAt":"2026-01-02T03:04:05Z"}"#).is_err());
}
