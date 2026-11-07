//! The non-UI logic of Scratchpad, ported from apple/Sources/ScratchpadCore.
//! The core never opens a file itself: everything goes through `Vault`.
pub mod text;
pub mod dates;
pub mod model;
pub mod json;
pub mod vault;
pub mod store;
pub mod formula;
pub mod paste;
pub mod sidebar;
pub mod sort;
pub mod rollover;
pub mod export;
pub mod archive;
