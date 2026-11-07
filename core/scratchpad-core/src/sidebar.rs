//! Sidebar grouping.
use crate::dates::{group_label, month_title, parts, short_date, Date};
use crate::model::Pad;
use crate::store::newest_first;
use std::collections::{HashMap, HashSet};

#[derive(Clone, Debug)]
pub struct SheetGroup<'a> { pub id: String, pub label: String, pub detail: String, pub sheets: Vec<&'a Pad> }

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TagSort { Alphabetical, MostSheets, RecentlyUsed }

fn dated(pads: &[Pad]) -> Vec<&Pad> {
    pads.iter().filter(|p| !p.pinned && p.date.is_some()).collect()
}

pub fn by_day<'a>(pads: &'a [Pad], today: &str) -> Vec<SheetGroup<'a>> {
    let mut list = dated(pads);
    list.sort_by(|a, b| newest_first(a, b));
    let mut groups: Vec<SheetGroup> = Vec::new();
    for p in list {
        let d = p.date.as_deref().unwrap();
        match groups.last_mut() {
            Some(g) if g.id == d => g.sheets.push(p),
            _ => groups.push(SheetGroup { id: d.to_string(), label: group_label(d, today), detail: short_date(d), sheets: vec![p] }),
        }
    }
    groups
}

pub fn by_month(pads: &[Pad]) -> Vec<SheetGroup<'_>> {
    let mut list = dated(pads);
    list.sort_by(|a, b| newest_first(a, b));
    let mut groups: Vec<SheetGroup> = Vec::new();
    for p in list {
        let d = p.date.as_deref().unwrap();
        let Some((y, m, _)) = parts(d) else { continue };
        let id: String = d.chars().take(7).collect();
        match groups.last_mut() {
            Some(g) if g.id == id => g.sheets.push(p),
            _ => groups.push(SheetGroup { id, label: month_title(y, m), detail: String::new(), sheets: vec![p] }),
        }
    }
    for g in &mut groups { g.detail = g.sheets.len().to_string(); }
    groups
}

pub fn recent(pads: &[Pad]) -> Vec<SheetGroup<'_>> {
    let mut list = dated(pads);
    list.sort_by(|a, b| b.updated_at.cmp(&a.updated_at).then_with(|| newest_first(a, b)));
    if list.is_empty() { return vec![]; }
    vec![SheetGroup { id: "recent".into(), label: "Recently edited".into(), detail: list.len().to_string(), sheets: list }]
}

pub fn by_tag(pads: &[Pad], sort: TagSort) -> Vec<SheetGroup<'_>> {
    let mut order: Vec<String> = Vec::new();
    let mut members: HashMap<String, Vec<&Pad>> = HashMap::new();
    let mut latest: HashMap<String, Date> = HashMap::new();
    let untagged = [String::new()];
    for p in pads {
        let tags: &[String] = if p.tags.is_empty() { &untagged } else { &p.tags };
        for t in tags {
            if !members.contains_key(t) { order.push(t.clone()); }
            members.entry(t.clone()).or_default().push(p);
            let e = latest.entry(t.clone()).or_insert(Date(i64::MIN));
            *e = (*e).max(p.updated_at);
        }
    }
    order.sort_by(|a, b| {
        if a.is_empty() != b.is_empty() { return a.is_empty().cmp(&b.is_empty()); }
        match sort {
            TagSort::Alphabetical => a.cmp(b),
            TagSort::MostSheets => members[b].len().cmp(&members[a].len()).then_with(|| a.cmp(b)),
            TagSort::RecentlyUsed => latest[b].cmp(&latest[a]).then_with(|| a.cmp(b)),
        }
    });
    order.into_iter().map(|k| {
        let mut sheets = members.remove(&k).unwrap_or_default();
        sheets.sort_by(|a, b| newest_first(a, b));
        SheetGroup { label: if k.is_empty() { "Untagged".into() } else { format!("#{}", k) }, detail: sheets.len().to_string(), id: k, sheets }
    }).collect()
}

pub fn pinned(pads: &[Pad]) -> Vec<&Pad> {
    let mut list: Vec<&Pad> = pads.iter().filter(|p| p.pinned).collect();
    list.sort_by_key(|p| p.display_title().to_lowercase());
    list
}

pub fn dates_with_sheets(pads: &[Pad]) -> HashSet<&str> {
    pads.iter().filter_map(|p| p.date.as_deref()).collect()
}
