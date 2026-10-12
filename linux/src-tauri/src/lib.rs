use base64::Engine;
use scratchpad_store::{Pad, Store};
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{Manager, State};

struct AppStore(Mutex<Store>);

fn err(e: impl std::fmt::Display) -> String { e.to_string() }

#[tauri::command]
fn list_pads(store: State<AppStore>) -> Result<Vec<Pad>, String> {
    store.0.lock().unwrap().list().map_err(err)
}

#[tauri::command]
fn load_pad(store: State<AppStore>, id: String) -> Result<Option<Pad>, String> {
    store.0.lock().unwrap().load(&id).map_err(err)
}

#[tauri::command]
fn today_pad(store: State<AppStore>) -> Result<Pad, String> {
    store.0.lock().unwrap().today().map_err(err)
}

#[tauri::command]
fn save_pad(store: State<AppStore>, pad: Pad) -> Result<(), String> {
    store.0.lock().unwrap().save(&pad).map_err(err)
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
    let (asset, name, size) = store.0.lock().unwrap().import_file(&PathBuf::from(path)).map_err(err)?;
    Ok(Imported { asset, name, size })
}

/// Absolute path for an asset, for the webview's asset protocol and for "reveal".
#[tauri::command]
fn asset_path(store: State<AppStore>, rel: String) -> Result<String, String> {
    store.0.lock().unwrap().asset_path(&rel).map(|p| p.to_string_lossy().to_string()).ok_or_else(|| "bad asset path".into())
}

/// Webview errors land on stderr in debug builds, so a headless run can be diagnosed.
#[tauri::command]
fn debug_log(msg: String) {
    if cfg!(debug_assertions) { eprintln!("[webview] {msg}"); }
}

#[tauri::command]
fn store_root(store: State<AppStore>) -> String {
    store.0.lock().unwrap().root.to_string_lossy().to_string()
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let root = app.path().app_data_dir()?;
            let store = Store::open(root)?;
            // Allow <img src> through the asset protocol for files under assets/.
            app.asset_protocol_scope().allow_directory(store.root.join("assets"), false)?;
            app.manage(AppStore(Mutex::new(store)));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![list_pads, load_pad, today_pad, save_pad, delete_pad, store_asset, import_file, asset_path, store_root, debug_log])
        .run(tauri::generate_context!())
        .expect("error while running scratchpad");
}
