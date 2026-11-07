//! Everything recorded from the Swift code in shared/vectors, replayed against the core.
//! Re-record only on purpose: `swift run core-check record` in apple/.
use scratchpad_core::dates::{self, Date};
use scratchpad_core::formula::{self, TableEvaluator};
use scratchpad_core::json::{encode_pad, encode_pads};
use scratchpad_core::model::*;
use scratchpad_core::paste::{self, ClipboardContents, PasteResult};
use scratchpad_core::sidebar::{self, SheetGroup, TagSort};
use scratchpad_core::sort::{sorted, MODES};
use scratchpad_core::{export, rollover};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::fs;
use std::path::Path;

struct V { input: Value, want: Value, pads: Vec<Pad>, today: String, now: Date }

fn load() -> V {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../shared/vectors");
    let input: Value = serde_json::from_slice(&fs::read(dir.join("inputs.json")).unwrap()).unwrap();
    let want: Value = serde_json::from_slice(&fs::read(dir.join("expected.json")).unwrap()).unwrap();
    let pads = input["sheets"].as_array().unwrap().iter().filter_map(|s| Pad::from_json(s.as_str().unwrap().as_bytes()).ok()).collect();
    let today = input["today"].as_str().unwrap().to_string();
    let now = Date::parse(input["now"].as_str().unwrap()).unwrap();
    V { input, want, pads, today, now }
}

fn each<'a>(v: &'a Value, key: &str) -> &'a Vec<Value> { v[key].as_array().unwrap_or_else(|| panic!("{key}")) }
fn s(v: &Value) -> &str { v.as_str().unwrap() }
fn group(g: &SheetGroup) -> Value { json!({"id": g.id, "label": g.label, "detail": g.detail, "sheets": g.sheets.iter().map(|p| p.id.clone()).collect::<Vec<_>>()}) }
fn groups(list: Vec<SheetGroup>) -> Value { Value::Array(list.iter().map(group).collect()) }

#[test]
fn the_file_format_is_byte_for_byte_what_swift_writes() {
    let v = load();
    let (input, want) = (each(&v.input, "sheets"), each(&v.want, "decoded"));
    assert_eq!(input.len(), want.len());
    let mut compared = 0;
    for (text, expected) in input.iter().zip(want) {
        let got = Pad::from_json(s(text).as_bytes());
        match expected.as_str() {
            None => assert!(got.is_err(), "Swift can't read this, the core can: {text}"),
            Some(bytes) => {
                let pad = got.unwrap_or_else(|e| panic!("Swift reads this, the core can't: {text}: {e}"));
                assert_eq!(String::from_utf8(encode_pad(&pad)).unwrap(), bytes, "from {text}");
                compared += 1;
            }
        }
    }
    assert!(compared > 50);
}

#[test]
fn dates() {
    let v = load();
    for (i, w) in each(&v.input, "isos").iter().zip(each(&v.want, "isos")) {
        assert_eq!(Date::parse(s(i)).map(|d| json!(d.0)).unwrap_or(Value::Null), *w, "{i}");
    }
    for (p, w) in each(&v.input, "phrases").iter().zip(each(&v.want, "phrases")) {
        assert_eq!(dates::parse_phrase(s(p), &v.today).map(Value::String).unwrap_or(Value::Null), *w, "{p}");
    }
    for (k, w) in each(&v.input, "keys").iter().zip(each(&v.want, "keyLabels")) {
        let k = s(k);
        assert_eq!(dates::short_date(k), s(&w["short"]), "{k}");
        assert_eq!(dates::long_date(Some(k)), s(&w["long"]), "{k}");
        assert_eq!(dates::medium_date(k), s(&w["medium"]), "{k}");
        assert_eq!(dates::group_label(k, &v.today), s(&w["group"]), "{k}");
        assert_eq!(dates::add_days(30, k).map(Value::String).unwrap_or(Value::Null), w["plus"], "{k}");
        assert_eq!(dates::distance(k, &v.today).map(|d| json!(d)).unwrap_or(Value::Null), w["distance"], "{k}");
        assert_eq!(dates::weekday_monday_first(k).map(|d| json!(d)).unwrap_or(Value::Null), w["weekday"], "{k}");
    }
    for (m, w) in each(&v.input, "months").iter().zip(each(&v.want, "months")) {
        let (y, mo) = (m[0].as_i64().unwrap(), m[1].as_i64().unwrap());
        assert_eq!(dates::month_title(y, mo), s(&w["title"]));
        assert_eq!(json!(dates::month_weeks(y, mo)), w["weeks"], "{y}-{mo}");
        let (sy, sm) = dates::month_shift(y, mo, -13);
        assert_eq!(json!([sy, sm]), w["shift"]);
    }
}

#[test]
fn numbers_and_tables() {
    let v = load();
    for (n, w) in each(&v.input, "numbers").iter().zip(each(&v.want, "numbers")) {
        let want = w.as_str().map(|t| t.parse::<f64>().unwrap());
        assert_eq!(formula::parse_number(s(n)), want, "{n}");
    }
    for (n, w) in each(&v.input, "formats").iter().zip(each(&v.want, "formats")) {
        assert_eq!(formula::format_number(n.as_f64().unwrap()), s(w), "{n}");
    }
    let tables: Vec<&Vec<Vec<String>>> = v.pads.iter().flat_map(|p| p.blocks.iter().filter_map(|b| b.rows.as_ref())).collect();
    let (want, md, fit) = (each(&v.want, "tables"), each(&v.want, "markdownTables"), each(&v.want, "fit"));
    assert_eq!(tables.len(), want.len());
    for (i, rows) in tables.iter().enumerate() {
        let mut e = TableEvaluator::new(rows);
        let got: Vec<Vec<String>> = rows.iter().enumerate().map(|(r, row)| (0..row.len()).map(|c| e.display(r, c)).collect()).collect();
        assert_eq!(json!(got), want[i], "table {i}");
        assert_eq!(export::table(rows), s(&md[i]), "table {i}");
        let cols = rows.iter().map(|r| r.len()).max().unwrap_or(0);
        assert_eq!(json!((0..cols).map(|c| fit_width(c, rows)).collect::<Vec<_>>()), fit[i], "table {i}");
    }
    let blocks: Vec<&Block> = v.pads.iter().flat_map(|p| p.blocks.iter()).filter(|b| b.kind == BlockKind::Table).collect();
    for (b, w) in blocks.iter().zip(each(&v.want, "widths")) { assert_eq!(json!(table_widths(b)), *w); }
}

#[test]
fn paste_and_titles() {
    let v = load();
    for (p, w) in each(&v.input, "pastes").iter().zip(each(&v.want, "pastes")) {
        let clip = ClipboardContents { plain: p["plain"].as_str().map(String::from), html: p["html"].as_str().map(String::from), ..Default::default() };
        let got: Vec<Value> = paste::classify(&clip, &|_| None).iter().map(|r| match r {
            PasteResult::Text(t) => json!({"kind": "text", "text": t}),
            PasteResult::Code(t, l) => json!({"kind": "code", "text": t, "language": l}),
            PasteResult::Link(u, t) => json!({"kind": "link", "url": u, "title": t}),
            PasteResult::Table(rows) => json!({"kind": "table", "rows": rows}),
            _ => json!({"kind": "other"}),
        }).collect();
        assert_eq!(Value::Array(got), *w, "{p}");
    }
    for (t, w) in each(&v.input, "titles").iter().zip(each(&v.want, "titles")) {
        assert_eq!(paste::html_title(s(t)).map(Value::String).unwrap_or(Value::Null), *w, "{t}");
    }
}

#[test]
fn small_rules() {
    let v = load();
    for (r, w) in each(&v.input, "rotations").iter().zip(each(&v.want, "rotations")) {
        assert_eq!(normalized_rotation(r.as_f64().unwrap()), s(w).parse::<f64>().unwrap(), "{r}");
    }
    for (n, w) in each(&v.input, "snaps").iter().zip(each(&v.want, "snaps")) { assert_eq!(json!(snapped(n.as_i64().unwrap())), *w, "{n}"); }
    for (t, w) in each(&v.input, "tags").iter().zip(each(&v.want, "tags")) { assert_eq!(tag_normalize(s(t)), s(w), "{t}"); }
    for (c, w) in each(&v.input, "slugs").iter().zip(each(&v.want, "slugs")) {
        let existing: HashSet<String> = c["existing"].as_array().unwrap().iter().map(|e| s(e).to_string()).collect();
        assert_eq!(slug(s(&c["title"]), &existing), s(w), "{c}");
    }
    let corner = |n: &str| match n { "topLeft" => Corner::TopLeft, "topRight" => Corner::TopRight, "bottomLeft" => Corner::BottomLeft, _ => Corner::BottomRight };
    let mut sample = Block::new("r".into(), BlockKind::Text, 240, 120, 300);
    sample.h = Some(200);
    for (r, w) in each(&v.input, "resizes").iter().zip(each(&v.want, "resized")) {
        let b = sample.resized(corner(s(&r["corner"])), r["dx"].as_f64().unwrap(), r["dy"].as_f64().unwrap(), r["start"].as_f64().unwrap(), r["aspect"].as_bool().unwrap());
        assert_eq!(json!([b.x, b.y, b.w, b.h.unwrap_or(-1)]), *w, "{r}");
    }
}

#[test]
fn sheets_say_what_swift_says() {
    let v = load();
    let queries: Vec<&str> = each(&v.input, "queries").iter().map(s).collect();
    let derived = each(&v.want, "derived");
    assert_eq!(v.pads.len(), derived.len());
    for (p, w) in v.pads.iter().zip(derived) {
        assert_eq!(p.display_title(), s(&w["displayTitle"]), "{}", p.id);
        assert_eq!(p.preview().map(Value::String).unwrap_or(Value::Null), w["preview"], "{}", p.id);
        assert_eq!(p.count_label(), s(&w["countLabel"]), "{}", p.id);
        assert_eq!(p.footer_label(), s(&w["footerLabel"]), "{}", p.id);
        assert_eq!(json!(queries.iter().map(|q| p.matches(q)).collect::<Vec<_>>()), w["matches"], "{}", p.id);
        assert_eq!(json!(p.compacted().todos.len()), w["compacted"], "{}", p.id);
    }
    for (p, w) in v.pads.iter().zip(each(&v.want, "markdown")) { assert_eq!(export::sheet(p), s(w), "{}", p.id); }
    let widths: Vec<Option<i64>> = each(&v.input, "widths").iter().map(Value::as_i64).collect();
    for (p, w) in v.pads.iter().zip(each(&v.want, "points")) {
        let got: Vec<[i64; 2]> = widths.iter().map(|x| { let (a, b) = paste::next_free_point(p, *x, paste::DEFAULT_WIDTH); [a, b] }).collect();
        assert_eq!(json!(got), *w, "{}", p.id);
    }
}

#[test]
fn lists_and_exports() {
    let v = load();
    let side = &v.want["sidebar"];
    assert_eq!(groups(sidebar::by_day(&v.pads, &v.today)), side["byDay"]);
    assert_eq!(groups(sidebar::by_month(&v.pads)), side["byMonth"]);
    assert_eq!(groups(sidebar::recent(&v.pads)), side["recent"]);
    assert_eq!(groups(sidebar::by_tag(&v.pads, TagSort::Alphabetical)), side["tagAlpha"]);
    assert_eq!(groups(sidebar::by_tag(&v.pads, TagSort::MostSheets)), side["tagMost"]);
    assert_eq!(groups(sidebar::by_tag(&v.pads, TagSort::RecentlyUsed)), side["tagRecent"]);
    assert_eq!(json!(sidebar::pinned(&v.pads).iter().map(|p| p.id.clone()).collect::<Vec<_>>()), v.want["pinned"]);
    let mut days: Vec<&str> = sidebar::dates_with_sheets(&v.pads).into_iter().collect();
    days.sort();
    assert_eq!(json!(days), v.want["datesWithSheets"]);
    assert_eq!(json!(tag_counts(&v.pads).iter().map(|(t, n)| [t.clone(), n.to_string()]).collect::<Vec<_>>()), v.want["tagCounts"]);
    assert_eq!(json!(tag_suggestions("w", &v.pads, &["work".to_string()]).iter().map(|x| x.0.clone()).collect::<Vec<_>>()), v.want["tagSuggestions"]);
    assert_eq!(export::everything(&v.pads), s(&v.want["everything"]));
    assert_eq!(export::todos(&v.pads, false, true, false), s(&v.want["todosDefault"]));
    assert_eq!(export::todos(&v.pads, false, false, true), s(&v.want["todosOpen"]));
    assert_eq!(export::todos(&v.pads, true, true, false), s(&v.want["todosAll"]));
    assert_eq!(export::todos(&v.pads[..1], false, true, false), s(&v.want["todosOne"]));
    let mut newest: Vec<Pad> = v.pads.iter().map(Pad::compacted).collect();
    newest.sort_by(scratchpad_core::store::newest_first);
    assert_eq!(String::from_utf8(encode_pads(&newest)).unwrap(), s(&v.want["exportJSON"]));
    for (k, w) in each(&v.input, "keys").iter().zip(each(&v.want, "sources")) {
        assert_eq!(json!(rollover::sources(s(k), &v.pads).iter().map(|p| p.id.clone()).collect::<Vec<_>>()), *w, "{k}");
    }
    let target = Pad::new("new".into(), Some(v.today.clone()), String::new(), &[], false, v.now);
    let carried = rollover::carried(&rollover::sources(&v.today, &v.pads), target);
    assert_eq!(json!(carried.todos.iter().map(|t| [t.text.clone(), t.carried_from.clone().unwrap_or_default()]).collect::<Vec<_>>()), v.want["carried"]);
}

#[test]
fn todo_order() {
    let v = load();
    for (list, w) in each(&v.input, "todoLists").iter().zip(each(&v.want, "sorts")) {
        let todos: Vec<Todo> = serde_json::from_value(list.clone()).unwrap();
        let mut got = Vec::new();
        for mode in MODES {
            for sinks in [false, true] { got.push(sorted(&todos, mode, sinks, v.now).iter().map(|t| t.id.clone()).collect::<Vec<_>>()); }
        }
        assert_eq!(json!(got), *w);
    }
}
