//! Kills under load, and old and new builds on one folder: rollback must stay possible.
use scratchpad_core::dates::Date;
use scratchpad_core::model::*;
use scratchpad_core::store::PadStore;
use scratchpad_core::vault::FsVault;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const NOW: Date = Date(1_794_000_000_000);

/// The `hammer` example. Cargo is asked where it is (building it if needed): `cargo test` doesn't
/// always leave target/<profile>/examples/hammer in place, and when the example is already fresh
/// (a restored CI cache) a plain build may not put that copy back either. The Linux CI failed on
/// both counts on 18 Nov once npm test passed again.
fn hammer() -> PathBuf {
    let test = std::env::current_exe().unwrap();
    let profile_dir = test.parent().unwrap().parent().unwrap().to_path_buf();
    let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
    let mut build = Command::new(cargo);
    build
        .args(["build", "-p", "scratchpad-core", "--example", "hammer", "--message-format=json"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .stderr(Stdio::inherit());
    if profile_dir.file_name().map_or(false, |p| p == "release") {
        build.arg("--release");
    }
    let out = build.output().unwrap();
    assert!(out.status.success(), "couldn't build the hammer example");
    let text = String::from_utf8_lossy(&out.stdout);
    for line in text.lines().filter(|l| l.contains("\"name\":\"hammer\"")) {
        let key = "\"executable\":\"";
        if let Some(start) = line.find(key) {
            let rest = &line[start + key.len()..];
            if let Some(end) = rest.find('"') {
                return PathBuf::from(&rest[..end]);
            }
        }
    }
    let fallback = profile_dir.join("examples/hammer");
    assert!(fallback.exists(), "cargo didn't say where the hammer example is");
    fallback
}

#[test]
fn a_kill_mid_save_leaves_the_last_whole_sheet() {
    let dir = tempfile::tempdir().unwrap();
    for round in 0..8 {
        let mut child = Command::new(hammer()).arg(dir.path()).stdout(Stdio::piped()).spawn().unwrap();
        let mut lines = BufReader::new(child.stdout.take().unwrap()).lines();
        let mut last = 0u64;
        for _ in 0..(3 + round * 2) { last = lines.next().unwrap().unwrap().parse().unwrap(); }
        child.kill().unwrap();
        child.wait().unwrap();
        let store = PadStore::new(FsVault::open(dir.path()).unwrap());
        let found = store.scan().unwrap();
        assert!(found.unreadable.is_empty(), "round {round}: {:?}", found.unreadable);
        let pad = store.load("hammered").unwrap().unwrap();
        let saved: u64 = pad.title.trim_start_matches("save ").parse().unwrap();
        assert!(saved >= last, "round {round}: lost a finished save: {saved} < {last}");
    }
}

fn sample(id: &str) -> Pad {
    let mut p = Pad::new(id.into(), Some("2026-01-02".into()), "Shared / \"sheet\" é".into(), &["work".to_string()], false, NOW);
    let mut table = Block::new("t".into(), BlockKind::Table, 24, 48, 240);
    table.rows = Some(vec![vec!["a".into(), "=1+1".into()]]);
    table.col_widths = Some(vec![120, 90]);
    table.rotation = -7.5;
    table.font = BlockFont::Hand;
    p.blocks.push(table);
    p.todos.push(Todo { id: "x".into(), text: "carry".into(), status: TodoStatus::Deferred, created_at: NOW, carried_from: Some("2026-01-01-aaaaaa".into()), extra: Extras::new() });
    p
}

/// Rollback: the old Linux store reads everything the core writes, and the other way round.
#[test]
fn the_old_linux_store_and_the_core_read_each_other() {
    let dir = tempfile::tempdir().unwrap();
    let core = PadStore::new(FsVault::open(dir.path()).unwrap());
    let old = scratchpad_store::Store::open(dir.path()).unwrap();
    core.save(&sample("by-core"), None).unwrap();
    let read = old.load("by-core").unwrap().unwrap();
    assert_eq!(read.title, "Shared / \"sheet\" é");
    assert_eq!(read.blocks[0].col_widths, Some(vec![120, 90]));
    assert_eq!(read.blocks[0].rotation, -7.5);
    assert_eq!(read.todos[0].carried_from.as_deref(), Some("2026-01-01-aaaaaa"));
    old.save(&read).unwrap();
    let back = core.load("by-core").unwrap().unwrap();
    assert_eq!((back.title.as_str(), back.blocks[0].font, back.todos[0].status), ("Shared / \"sheet\" é", BlockFont::Hand, TodoStatus::Deferred));
    let by_old = old.today_for("2026-02-02").unwrap();
    let got = core.load(&by_old.id).unwrap().unwrap();
    assert_eq!(got.date.as_deref(), Some("2026-02-02"));
    assert!(core.scan().unwrap().unreadable.is_empty());
    assert!(old.unreadable().unwrap().is_empty());
}

fn written(dir: &Path, id: &str) -> Vec<u8> { fs::read(dir.join(format!("pads/{id}.json"))).unwrap() }

#[test]
fn saving_the_same_sheet_twice_writes_the_same_bytes() {
    let dir = tempfile::tempdir().unwrap();
    let store = PadStore::new(FsVault::open(dir.path()).unwrap());
    store.save(&sample("a"), None).unwrap();
    let first = written(dir.path(), "a");
    let pad = store.load("a").unwrap().unwrap();
    store.save(&pad, None).unwrap();
    assert_eq!(written(dir.path(), "a"), first, "a synced folder would churn");
}
