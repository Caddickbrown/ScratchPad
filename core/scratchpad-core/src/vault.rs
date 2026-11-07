//! Quire's rule: the core never opens a file itself. `FsVault` serves Linux and tests;
//! `AppleVault` in Swift adds file coordination and iCloud placeholders.
use std::fs;
use std::io::Write;
use std::path::{Component, Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VaultError(pub String);

impl std::fmt::Display for VaultError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { f.write_str(&self.0) }
}

impl From<std::io::Error> for VaultError {
    fn from(e: std::io::Error) -> VaultError { VaultError(e.to_string()) }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum EntryState { Available, NotDownloaded }

/// `path` is relative to the vault, as if the file were here. A not-downloaded sheet is listed
/// under its real name, whatever stand-in the platform keeps for it.
#[derive(Clone, Debug, PartialEq)]
pub struct VaultEntry { pub path: String, pub modified: Option<f64>, pub state: EntryState }

pub trait Vault: Send + Sync {
    fn list(&self, dir: &str) -> Result<Vec<VaultEntry>, VaultError>;
    fn read(&self, path: &str) -> Result<Vec<u8>, VaultError>;
    /// Atomic: a reader sees the old file or the new one, never part of either.
    fn write(&self, path: &str, data: &[u8]) -> Result<(), VaultError>;
    fn remove(&self, path: &str) -> Result<(), VaultError>;
    fn exists(&self, path: &str) -> bool;
    /// For showing an image.
    fn local_url(&self, path: &str) -> Option<String>;
}

impl<V: Vault + ?Sized> Vault for std::sync::Arc<V> {
    fn list(&self, dir: &str) -> Result<Vec<VaultEntry>, VaultError> { (**self).list(dir) }
    fn read(&self, path: &str) -> Result<Vec<u8>, VaultError> { (**self).read(path) }
    fn write(&self, path: &str, data: &[u8]) -> Result<(), VaultError> { (**self).write(path, data) }
    fn remove(&self, path: &str) -> Result<(), VaultError> { (**self).remove(path) }
    fn exists(&self, path: &str) -> bool { (**self).exists(path) }
    fn local_url(&self, path: &str) -> Option<String> { (**self).local_url(path) }
}

pub struct FsVault { root: PathBuf }

impl FsVault {
    pub fn open(root: impl Into<PathBuf>) -> Result<FsVault, VaultError> {
        let root = root.into();
        fs::create_dir_all(root.join("pads"))?;
        fs::create_dir_all(root.join("assets"))?;
        Ok(FsVault { root })
    }

    pub fn root(&self) -> &Path { &self.root }

    /// The file for a vault path. Anything that would leave the root is refused.
    fn at(&self, path: &str) -> Result<PathBuf, VaultError> {
        let rel = Path::new(path);
        if rel.components().all(|c| matches!(c, Component::Normal(_))) { Ok(self.root.join(rel)) }
        else { Err(VaultError(format!("outside the store: {path}"))) }
    }
}

/// Named so it's hidden from `list`, and on disk before it takes the real name.
fn atomic_write(dest: &Path, data: &[u8]) -> std::io::Result<()> {
    let name = dest.file_name().and_then(|n| n.to_str()).unwrap_or("file");
    let tmp = dest.with_file_name(format!(".{}.{}.tmp", name, uuid::Uuid::new_v4().simple()));
    let written = (|| {
        let mut file = fs::File::create(&tmp)?;
        file.write_all(data)?;
        file.sync_all()?;
        fs::rename(&tmp, dest)
    })();
    if written.is_err() { let _ = fs::remove_file(&tmp); }
    written
}

impl Vault for FsVault {
    fn list(&self, dir: &str) -> Result<Vec<VaultEntry>, VaultError> {
        let mut out = Vec::new();
        for e in fs::read_dir(self.at(dir)?)? {
            let e = e?;
            let modified = e.metadata().ok().and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs_f64());
            out.push(VaultEntry { path: format!("{}/{}", dir, e.file_name().to_string_lossy()), modified, state: EntryState::Available });
        }
        Ok(out)
    }
    fn read(&self, path: &str) -> Result<Vec<u8>, VaultError> { Ok(fs::read(self.at(path)?)?) }
    fn write(&self, path: &str, data: &[u8]) -> Result<(), VaultError> { Ok(atomic_write(&self.at(path)?, data)?) }
    fn remove(&self, path: &str) -> Result<(), VaultError> { Ok(fs::remove_file(self.at(path)?)?) }
    fn exists(&self, path: &str) -> bool { self.at(path).map(|p| p.exists()).unwrap_or(false) }
    fn local_url(&self, path: &str) -> Option<String> { self.at(path).ok().map(|p| p.to_string_lossy().into_owned()) }
}
