//! Saves one big sheet in a loop until killed, for tests/lifecycle.rs. Prints each title as it lands.
use scratchpad_core::dates::Date;
use scratchpad_core::model::*;
use scratchpad_core::store::PadStore;
use scratchpad_core::vault::FsVault;
use std::io::Write;

fn main() {
    let dir = std::env::args().nth(1).unwrap();
    let store = PadStore::new(FsVault::open(dir).unwrap());
    let mut pad = Pad::new("hammered".into(), None, String::new(), &[], true, Date(1_794_000_000_000));
    let mut block = Block::new("b".into(), BlockKind::Text, 0, 0, 96);
    block.text = Some("line of text ".repeat(20_000));
    pad.blocks.push(block);
    let mut out = std::io::stdout();
    for n in 0u64.. {
        pad.title = format!("save {n}");
        store.save(&pad, None).unwrap();
        writeln!(out, "{n}").unwrap();
        out.flush().unwrap();
    }
}
