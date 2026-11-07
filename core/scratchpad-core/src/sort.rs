//! To-do column view order.
use crate::dates::Date;
use crate::model::{Pad, Todo, TodoStatus};
use crate::text::localized_cmp;
use std::cmp::Ordering;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TodoSortMode { Manual, OpenFirst, OverdueFirst, Alphabetical, OldestFirst }

pub const MODES: [TodoSortMode; 5] = [TodoSortMode::Manual, TodoSortMode::OpenFirst, TodoSortMode::OverdueFirst, TodoSortMode::Alphabetical, TodoSortMode::OldestFirst];

fn rank(s: TodoStatus) -> i32 {
    match s { TodoStatus::Open => 0, TodoStatus::Deferred => 1, TodoStatus::Done => 2 }
}

impl TodoSortMode {
    pub fn from_name(s: &str) -> TodoSortMode {
        match s {
            "openFirst" => TodoSortMode::OpenFirst, "overdueFirst" => TodoSortMode::OverdueFirst,
            "alphabetical" => TodoSortMode::Alphabetical, "oldestFirst" => TodoSortMode::OldestFirst,
            _ => TodoSortMode::Manual,
        }
    }
}

pub fn sorted(todos: &[Todo], mode: TodoSortMode, done_sinks: bool, now: Date) -> Vec<Todo> {
    sorted_indices(todos, mode, done_sinks, now).into_iter().map(|i| todos[i].clone()).collect()
}

/// A stable sort, as positions in `todos`: Empty rows always stay last, and `done_sinks` pushes
/// done rows to the bottom in every mode, Manual included.
pub fn sorted_indices(todos: &[Todo], mode: TodoSortMode, done_sinks: bool, now: Date) -> Vec<usize> {
    let mut out: Vec<usize> = (0..todos.len()).collect();
    out.sort_by(|&x, &y| {
        let (a, b) = (&todos[x], &todos[y]);
        if a.is_filled() != b.is_filled() { return if a.is_filled() { Ordering::Less } else { Ordering::Greater }; }
        if done_sinks {
            let (da, db) = (a.status == TodoStatus::Done, b.status == TodoStatus::Done);
            if da != db { return da.cmp(&db); }
        }
        match mode {
            TodoSortMode::Manual => Ordering::Equal,
            TodoSortMode::OpenFirst => rank(a.status).cmp(&rank(b.status)),
            TodoSortMode::OverdueFirst => (!a.is_overdue(now)).cmp(&!b.is_overdue(now)).then_with(|| rank(a.status).cmp(&rank(b.status))),
            TodoSortMode::Alphabetical => localized_cmp(&a.text, &b.text),
            TodoSortMode::OldestFirst => a.created_at.cmp(&b.created_at),
        }
    });
    out
}

pub fn committing_view_order(pad: &Pad, mode: TodoSortMode, done_sinks: bool, now: Date) -> Pad {
    let mut p = pad.clone();
    p.todos = sorted(&pad.todos, mode, done_sinks, now);
    p
}
