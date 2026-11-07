//! `.scratchpad` archive: `{ format, v, exportedAt, sheets, assets }`.
use crate::dates::Date;
use crate::json::encode_archive;
use crate::model::*;
use crate::store::{newest_first, PadStore, Result};
use crate::vault::Vault;
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use serde::Deserialize;
use std::collections::{BTreeMap, HashMap};

pub const FORMAT_NAME: &str = "scratchpad-archive";

pub struct Archive { pub exported_at: Date, pub sheets: Vec<Pad>, pub assets: BTreeMap<String, String> }

#[derive(Debug, PartialEq, Eq)]
pub struct ImportResult { pub sheets: usize, pub overwritten: usize, pub assets_written: usize, pub skipped: usize, pub kept_newer: usize }

pub fn is_safe_asset_path(path: &str) -> bool {
    let Some(name) = path.strip_prefix("assets/") else { return false };
    let b = name.as_bytes();
    !b.is_empty() && b.len() <= 201 && b[0].is_ascii_alphanumeric() && !path.contains("..")
        && b.iter().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'.' | b'_' | b'-'))
}

#[derive(Deserialize)]
struct Raw {
    format: String,
    #[allow(dead_code)] v: i64,
    #[serde(rename = "exportedAt")] exported_at: String,
    sheets: Vec<Pad>,
    assets: BTreeMap<String, String>,
}

impl Archive {
    pub fn build<V: Vault>(sheets: &[Pad], store: &PadStore<V>, now: Date) -> Archive {
        let mut assets = BTreeMap::new();
        for p in sheets {
            for b in &p.blocks {
                let Some(a) = b.asset.as_ref() else { continue };
                if !is_safe_asset_path(a) || assets.contains_key(a) { continue; }
                if let Ok(data) = store.vault.read(a) {
                    assets.insert(a.clone(), STANDARD.encode(data));
                }
            }
        }
        let mut list: Vec<Pad> = sheets.iter().map(Pad::compacted).collect();
        list.sort_by(newest_first);
        Archive { exported_at: now, sheets: list, assets }
    }

    pub fn encoded(&self) -> Vec<u8> {
        let assets: Vec<(String, String)> = self.assets.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
        encode_archive(&self.sheets, &assets, self.exported_at, FORMAT_NAME, 1)
    }

    pub fn decode(data: &[u8]) -> Option<Archive> {
        let raw: Raw = serde_json::from_slice(data).ok()?;
        if raw.format != FORMAT_NAME { return None; }
        Some(Archive { exported_at: Date::parse(&raw.exported_at)?, sheets: raw.sheets, assets: raw.assets })
    }

    /// Merges into the store, assets first so a sheet never arrives before what it shows. A sheet
    /// replaces one with the same id only if it's newer, so an old backup can't undo later work.
    /// Assets are written only if missing. Invalid ids and unsafe asset paths are skipped, and so
    /// are sheets that won't read or haven't arrived: there's nothing to compare them with.
    pub fn import_into<V: Vault>(&self, store: &PadStore<V>) -> Result<ImportResult> {
        let mut result = ImportResult { sheets: 0, overwritten: 0, assets_written: 0, skipped: 0, kept_newer: 0 };
        for (path, b64) in &self.assets {
            let data = if is_safe_asset_path(path) { STANDARD.decode(b64).ok() } else { None };
            let Some(data) = data else { result.skipped += 1; continue };
            if store.vault.exists(path) { continue; }
            store.vault.write(path, &data)?;
            result.assets_written += 1;
        }
        let scan = store.scan()?;
        let uncertain = scan.uncertain_ids();
        let existing: HashMap<&str, Date> = scan.sheets.iter().map(|p| (p.id.as_str(), p.updated_at)).collect();
        for s in &self.sheets {
            if !is_valid_id(&s.id) || uncertain.contains(&s.id) { result.skipped += 1; continue; }
            if let Some(here) = existing.get(s.id.as_str()) {
                if *here >= s.updated_at { result.kept_newer += 1; continue; }
                result.overwritten += 1;
            }
            store.save(s, None)?;
            result.sheets += 1;
        }
        Ok(result)
    }
}
