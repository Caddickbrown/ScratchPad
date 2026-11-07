use base64::Engine;
use scratchpad_core::archive::{is_safe_asset_path, Archive};
use scratchpad_core::dates::Date;
use scratchpad_core::model::Pad;
use scratchpad_core::paste::html_title;
use scratchpad_core::store::PadStore;
use scratchpad_core::vault::{FsVault, Vault};
use std::io::Read;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{Manager, State};

struct AppStore(Mutex<PadStore<FsVault>>);

fn err(e: impl std::fmt::Display) -> String { e.to_string() }

/// The local day, which only the shell knows.
fn today_key() -> String { chrono::Local::now().format("%Y-%m-%d").to_string() }

#[tauri::command]
fn list_pads(store: State<AppStore>) -> Result<Vec<Pad>, String> {
    store.0.lock().unwrap().list().map_err(err)
}

#[tauri::command]
fn unreadable_pads(store: State<AppStore>) -> Result<Vec<String>, String> {
    Ok(store.0.lock().unwrap().scan().map_err(err)?.unreadable)
}

#[tauri::command]
fn load_pad(store: State<AppStore>, id: String) -> Result<Option<Pad>, String> {
    store.0.lock().unwrap().load(&id).map_err(err)
}

#[tauri::command]
fn today_pad(store: State<AppStore>) -> Result<Pad, String> {
    store.0.lock().unwrap().today(Date::now(), &today_key(), false).map_err(err)
}

#[tauri::command]
fn save_pad(store: State<AppStore>, pad: Pad) -> Result<(), String> {
    store.0.lock().unwrap().save(&pad, Some(Date::now())).map(|_| ()).map_err(err)
}

#[tauri::command]
fn delete_pad(store: State<AppStore>, id: String) -> Result<(), String> {
    store.0.lock().unwrap().delete(&id).map_err(err)
}

#[derive(serde::Serialize)]
struct Imported { asset: String, name: String, size: u64 }

/// Bytes from the webview (pasted image) as base64; returns the store-relative asset path.
#[tauri::command]
fn store_asset(store: State<AppStore>, base64_data: String, ext: String) -> Result<String, String> {
    let bytes = base64::engine::general_purpose::STANDARD.decode(base64_data).map_err(err)?;
    store.0.lock().unwrap().store_asset(&bytes, &ext).map_err(err)
}

/// A dropped or pasted file path, copied into assets/.
#[tauri::command]
fn import_file(store: State<AppStore>, path: String) -> Result<Imported, String> {
    let path = PathBuf::from(path);
    let bytes = std::fs::read(&path).map_err(err)?;
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
    let asset = store.0.lock().unwrap().store_asset(&bytes, ext).map_err(err)?;
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("file").to_string();
    Ok(Imported { asset, name, size: bytes.len() as u64 })
}

/// Absolute path for an asset, for the webview's asset protocol and for "reveal".
#[tauri::command]
fn asset_path(store: State<AppStore>, rel: String) -> Result<String, String> {
    if !is_safe_asset_path(&rel) { return Err("bad asset path".into()); }
    store.0.lock().unwrap().vault.local_url(&rel).ok_or_else(|| "bad asset path".into())
}

/// Webview boot and error lines land on stderr, so a headless run can be diagnosed.
#[tauri::command]
fn debug_log(msg: String) {
    eprintln!("[webview] {msg}");
}

/// Page title for a pasted link. Best effort: 5 s timeout, first 256 KB, http(s) only.
#[tauri::command]
async fn fetch_title(url: String) -> Result<Option<String>, String> {
    if !(url.starts_with("http://") || url.starts_with("https://")) { return Err("not http".into()); }
    tauri::async_runtime::spawn_blocking(move || {
        let agent = ureq::AgentBuilder::new().timeout(std::time::Duration::from_secs(5)).build();
        let resp = agent.get(&url).set("User-Agent", "Scratchpad/0.1").call().map_err(err)?;
        let mut body = String::new();
        resp.into_reader().take(256 * 1024).read_to_string(&mut body).map_err(err)?;
        Ok(html_title(&body))
    }).await.map_err(err)?
}

/// Every sheet (or one tag's) plus its assets as a `.scratchpad` archive JSON string. The page writes it via the save dialog.
#[tauri::command]
fn archive_json(store: State<AppStore>, tag: Option<String>) -> Result<String, String> {
    let store = store.0.lock().unwrap();
    let sheets: Vec<Pad> = store.list().map_err(err)?.into_iter()
        .filter(|p| tag.as_ref().map(|t| p.tags.contains(t)).unwrap_or(true)).collect();
    String::from_utf8(Archive::build(&sheets, &store, Date::now()).encoded()).map_err(err)
}

#[derive(serde::Serialize)]
struct ImportSummary { sheets: usize, assets: usize, kept_newer: usize, skipped: usize }

/// Merge an archive the page read from a file the user picked.
#[tauri::command]
fn import_archive_json(store: State<AppStore>, json: String) -> Result<ImportSummary, String> {
    let archive = Archive::decode(json.as_bytes()).ok_or("That file is not a Scratchpad archive")?;
    let r = archive.import_into(&store.0.lock().unwrap()).map_err(err)?;
    Ok(ImportSummary { sheets: r.sheets, assets: r.assets_written, kept_newer: r.kept_newer, skipped: r.skipped })
}

#[tauri::command]
fn store_root(store: State<AppStore>) -> String {
    store.0.lock().unwrap().vault.root().to_string_lossy().to_string()
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .setup(|app| {
            let root = app.path().app_data_dir()?;
            let vault = FsVault::open(root).map_err(|e| e.to_string())?;
            // Allow <img src> through the asset protocol for files under assets/.
            app.asset_protocol_scope().allow_directory(vault.root().join("assets"), false)?;
            app.manage(AppStore(Mutex::new(PadStore::new(vault))));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![list_pads, unreadable_pads, load_pad, today_pad, save_pad, delete_pad, store_asset, import_file, asset_path, store_root, debug_log, fetch_title, archive_json, import_archive_json])
        .run(tauri::generate_context!())
        .expect("error while running scratchpad");
}
