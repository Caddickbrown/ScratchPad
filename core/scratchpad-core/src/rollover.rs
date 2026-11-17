//! Carry-over.
use crate::model::{new_uuid, Pad, Todo, TodoStatus};

pub fn carried(sources: &[&Pad], mut target: Pad) -> Pad {
    let mut ordered: Vec<&&Pad> = sources.iter().collect();
    ordered.sort_by_key(|p| p.created_at);
    let mut carry: Vec<Todo> = Vec::new();
    for source in ordered {
        for t in source.todos.iter().filter(|t| t.is_filled() && t.status != TodoStatus::Done) {
            carry.push(Todo { id: new_uuid(), text: t.text.clone(), status: TodoStatus::Open, created_at: t.created_at, carried_from: Some(source.id.clone()), extra: Default::default() });
        }
    }
    carry.append(&mut target.todos);
    target.todos = carry;
    target
}

/// Every unpinned sheet of the latest date strictly before `day`.
pub fn sources<'a>(day: &str, pads: &'a [Pad]) -> Vec<&'a Pad> {
    let earlier: Vec<&Pad> = pads.iter().filter(|p| !p.pinned && p.date.as_deref().map(|d| d < day).unwrap_or(false)).collect();
    let Some(latest) = earlier.iter().filter_map(|p| p.date.as_deref()).max() else { return vec![] };
    earlier.iter().copied().filter(|p| p.date.as_deref() == Some(latest)).collect()
}

/// What coming back to the app should do, once anything typed has been saved.
#[derive(Clone, PartialEq, Debug)]
pub enum ResumeStep {
    Nothing,
    /// Another device saved this sheet since it was opened.
    Load(Pad),
    OpenToday,
    /// No sheet is open and the app doesn't make one each day: open the one last changed.
    OpenLatest,
}

/// A new day moves on from the sheet that was today's, and leaves any other sheet where it is.
/// A sheet that's newer on disk replaces the copy in memory, which would otherwise overwrite it.
pub fn resume_step(current: Option<&Pad>, on_disk: Option<&Pad>, last_today: &str, today: &str) -> ResumeStep {
    resume_step_with(current, on_disk, last_today, today, true)
}

/// `resume_step`, with the "New sheet each day" setting. Off (the default since 17 Nov), a new day leaves the
/// open sheet where it is, and with none open the one last changed opens: only New makes a sheet.
pub fn resume_step_with(current: Option<&Pad>, on_disk: Option<&Pad>, last_today: &str, today: &str,
                        new_sheet_each_day: bool) -> ResumeStep {
    let Some(current) = current else {
        return if new_sheet_each_day { ResumeStep::OpenToday } else { ResumeStep::OpenLatest };
    };
    if new_sheet_each_day && last_today != today && current.date.as_deref() == Some(last_today) { return ResumeStep::OpenToday; }
    match on_disk {
        Some(p) if p.updated_at > current.updated_at => ResumeStep::Load(p.clone()),
        _ => ResumeStep::Nothing,
    }
}
