//! The shape JSONEncoder writes with [.prettyPrinted, .sortedKeys] and .iso8601 dates,
//! byte for byte, so a synced folder does not churn between writers.
use crate::model::{Block, Extras, Pad, Todo};
use std::collections::btree_map;
use std::iter::Peekable;

type Rest<'a> = Peekable<btree_map::Iter<'a, String, serde_json::Value>>;

struct W { out: Vec<u8>, depth: usize }

impl W {
    fn indent(&mut self) { for _ in 0..self.depth { self.out.extend_from_slice(b"  "); } }

    fn string(&mut self, s: &str) {
        self.out.push(b'"');
        let bytes = s.as_bytes();
        let mut start = 0;
        for (i, &b) in bytes.iter().enumerate() {
            let esc: Option<&[u8]> = match b {
                b'"' => Some(b"\\\""),
                b'\\' => Some(b"\\\\"),
                b'/' => Some(b"\\/"),
                b'\n' => Some(b"\\n"),
                b'\r' => Some(b"\\r"),
                b'\t' => Some(b"\\t"),
                0x08 => Some(b"\\b"),
                0x0c => Some(b"\\f"),
                0..=0x1f => None,
                _ => continue,
            };
            self.out.extend_from_slice(&bytes[start..i]);
            match esc {
                Some(e) => self.out.extend_from_slice(e),
                None => self.out.extend_from_slice(format!("\\u{:04x}", b).as_bytes()),
            }
            start = i + 1;
        }
        self.out.extend_from_slice(&bytes[start..]);
        self.out.push(b'"');
    }

    fn key(&mut self, first: &mut bool, k: &str) {
        if !*first { self.out.extend_from_slice(b",\n"); }
        *first = false;
        self.indent();
        self.string(k);
        self.out.extend_from_slice(b" : ");
    }

    /// A known key, after any unknown ones that sort before it.
    fn known(&mut self, first: &mut bool, rest: &mut Rest, k: &str) {
        while rest.peek().is_some_and(|(e, _)| e.as_str() < k) {
            let (e, v) = rest.next().unwrap();
            self.key(first, e);
            self.value(v);
        }
        self.key(first, k);
    }

    fn rest(&mut self, first: &mut bool, rest: &mut Rest) {
        for (e, v) in rest { self.key(first, e); self.value(v); }
    }

    /// An unknown field, in the same layout as everything else.
    fn value(&mut self, v: &serde_json::Value) {
        use serde_json::Value::*;
        match v {
            Null => self.null(),
            Bool(b) => self.bool(*b),
            Number(n) => self.out.extend_from_slice(n.to_string().as_bytes()),
            String(s) => self.string(s),
            Array(a) => self.array(a, |w, x| w.value(x)),
            Object(o) if o.is_empty() => {
                self.out.extend_from_slice(b"{\n\n");
                self.indent();
                self.out.push(b'}');
            }
            Object(o) => {
                self.open_obj();
                let f = &mut true;
                for (k, x) in o { self.key(f, k); self.value(x); }
                self.close_obj();
            }
        }
    }

    fn open_obj(&mut self) { self.out.extend_from_slice(b"{\n"); self.depth += 1; }
    fn close_obj(&mut self) { self.out.push(b'\n'); self.depth -= 1; self.indent(); self.out.push(b'}'); }

    fn array<T>(&mut self, items: &[T], mut each: impl FnMut(&mut W, &T)) {
        self.out.extend_from_slice(b"[\n");
        self.depth += 1;
        if items.is_empty() {
            self.out.push(b'\n');
        } else {
            for (i, x) in items.iter().enumerate() {
                if i > 0 { self.out.extend_from_slice(b",\n"); }
                self.indent();
                each(self, x);
            }
            self.out.push(b'\n');
        }
        self.depth -= 1;
        self.indent();
        self.out.push(b']');
    }

    fn num(&mut self, v: i64) { self.out.extend_from_slice(v.to_string().as_bytes()); }

    fn bool(&mut self, v: bool) { self.out.extend_from_slice(if v { b"true" } else { b"false" }); }

    fn null(&mut self) { self.out.extend_from_slice(b"null"); }

    fn opt_str(&mut self, first: &mut bool, rest: &mut Rest, k: &str, v: &Option<String>) {
        if let Some(s) = v {
            self.known(first, rest, k);
            self.string(s);
        }
    }

    fn block(&mut self, b: &Block) {
        self.open_obj();
        let (f, r) = (&mut true, &mut extras(&b.extra));
        self.opt_str(f, r, "asset", &b.asset);
        self.known(f, r, "bold"); self.bool(b.bold);
        self.opt_str(f, r, "caption", &b.caption);
        if let Some(c) = &b.col_widths {
            self.known(f, r, "colWidths");
            self.array(c, |w, x| w.num(*x));
        }
        self.known(f, r, "font"); self.string(b.font.name());
        self.known(f, r, "fontSize"); self.num(b.font_size);
        self.known(f, r, "h");
        match b.h { Some(h) => self.num(h), None => self.null() }
        self.known(f, r, "id"); self.string(&b.id);
        self.known(f, r, "italic"); self.bool(b.italic);
        self.known(f, r, "kind"); self.string(b.kind.name());
        self.opt_str(f, r, "language", &b.language);
        self.opt_str(f, r, "name", &b.name);
        self.known(f, r, "rotation");
        self.out.extend_from_slice(format!("{}", b.rotation).as_bytes());
        if let Some(rows) = &b.rows {
            self.known(f, r, "rows");
            self.array(rows, |w, row| w.array(row, |w, c| w.string(c)));
        }
        if let Some(size) = b.size { self.known(f, r, "size"); self.num(size); }
        self.opt_str(f, r, "text", &b.text);
        self.opt_str(f, r, "url", &b.url);
        self.known(f, r, "w"); self.num(b.w);
        self.known(f, r, "x"); self.num(b.x);
        self.known(f, r, "y"); self.num(b.y);
        self.rest(f, r);
        self.close_obj();
    }

    fn todo(&mut self, t: &Todo) {
        self.open_obj();
        let (f, r) = (&mut true, &mut extras(&t.extra));
        self.known(f, r, "carriedFrom");
        match &t.carried_from { Some(c) => self.string(c), None => self.null() }
        self.known(f, r, "createdAt"); self.string(&t.created_at.iso());
        self.known(f, r, "id"); self.string(&t.id);
        self.known(f, r, "status"); self.string(t.status.name());
        self.known(f, r, "text"); self.string(&t.text);
        self.rest(f, r);
        self.close_obj();
    }

    fn pad(&mut self, p: &Pad) {
        self.open_obj();
        let (f, r) = (&mut true, &mut extras(&p.extra));
        self.known(f, r, "blocks");
        self.array(&p.blocks, |w, b| w.block(b));
        self.known(f, r, "createdAt"); self.string(&p.created_at.iso());
        self.known(f, r, "date");
        match &p.date { Some(d) => self.string(d), None => self.null() }
        self.known(f, r, "id"); self.string(&p.id);
        self.known(f, r, "pinned"); self.bool(p.pinned);
        self.known(f, r, "tags");
        self.array(&p.tags, |w, t| w.string(t));
        self.known(f, r, "title"); self.string(&p.title);
        self.known(f, r, "todos");
        self.array(&p.todos, |w, t| w.todo(t));
        self.known(f, r, "updatedAt"); self.string(&p.updated_at.iso());
        self.known(f, r, "v"); self.num(crate::model::FORMAT_VERSION);
        self.rest(f, r);
        self.close_obj();
    }
}

fn extras(e: &Extras) -> Rest<'_> { e.iter().peekable() }

pub fn encode_pad(p: &Pad) -> Vec<u8> {
    let mut w = W { out: Vec::with_capacity(4096), depth: 0 };
    w.pad(p);
    w.out
}

pub fn encode_pads(pads: &[Pad]) -> Vec<u8> {
    let mut w = W { out: Vec::with_capacity(1 << 20), depth: 0 };
    w.array(pads, |w, p| w.pad(p));
    w.out
}

/// `{ assets, exportedAt, format, sheets, v }`, sorted keys, assets sorted too.
pub fn encode_archive(pads: &[Pad], assets: &[(String, String)], exported_at: crate::dates::Date, format: &str, v: i64) -> Vec<u8> {
    let mut w = W { out: Vec::with_capacity(1 << 22), depth: 0 };
    w.open_obj();
    let f = &mut true;
    w.key(f, "assets");
    if assets.is_empty() {
        w.out.extend_from_slice(b"{\n\n");
        w.indent();
        w.out.push(b'}');
    } else {
        w.open_obj();
        let g = &mut true;
        for (k, b64) in assets {
            w.key(g, k);
            w.string(b64);
        }
        w.close_obj();
    }
    w.key(f, "exportedAt"); w.string(&exported_at.iso());
    w.key(f, "format"); w.string(format);
    w.key(f, "sheets");
    w.array(pads, |w, p| w.pad(p));
    w.key(f, "v"); w.num(v);
    w.close_obj();
    w.out
}
