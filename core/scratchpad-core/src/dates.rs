//! DayMath, DayLabel, DatePhrase, MonthGrid and ISODate.
use crate::text::{graphemes, trim_all};
use regex::Regex;
use std::sync::OnceLock;

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (m + if m > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (yoe + era * 400 + if m <= 2 { 1 } else { 0 }, m, d)
}

/// Milliseconds since 1970. ISO8601DateFormatter keeps three fractional digits.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub struct Date(pub i64);

impl Date {
    /// ISODate.parse: strict shape, lenient values, as Foundation's formatter is.
    pub fn parse(s: &str) -> Option<Date> {
        let b = s.as_bytes();
        if b.len() < 20 { return None; }
        let num = |r: std::ops::Range<usize>| -> Option<i64> {
            let mut v = 0i64;
            for &c in &b[r] {
                if !c.is_ascii_digit() { return None; }
                v = v * 10 + (c - b'0') as i64;
            }
            Some(v)
        };
        if b[4] != b'-' || b[7] != b'-' || b[10] != b'T' || b[13] != b':' || b[16] != b':' { return None; }
        let (y, mo, d) = (num(0..4)?, num(5..7)?, num(8..10)?);
        let (h, mi, sec) = (num(11..13)?, num(14..16)?, num(17..19)?);
        if !(1..=12).contains(&mo) || !(1..=31).contains(&d) || h > 24 || mi > 59 || sec > 59 { return None; }
        let mut i = 19;
        let mut millis = 0;
        if b[i] == b'.' {
            i += 1;
            let start = i;
            let mut scale = 100;
            while i < b.len() && b[i].is_ascii_digit() {
                millis += (b[i] - b'0') as i64 * scale;
                scale /= 10;
                i += 1;
            }
            if i == start { return None; }
        }
        let offset = match b.get(i)? {
            b'Z' if i + 1 == b.len() => 0,
            sign @ (b'+' | b'-') => {
                let minutes = match b.len() - i {
                    6 if b[i + 3] == b':' => i + 4,
                    5 => i + 3,
                    _ => return None,
                };
                let v = num(i + 1..i + 3)? * 3600 + num(minutes..minutes + 2)? * 60;
                if *sign == b'-' { -v } else { v }
            }
            _ => return None,
        };
        let secs = days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + sec - offset;
        Some(Date(secs * 1000 + millis))
    }

    /// `.iso8601` encoding: UTC, whole seconds, truncated.
    pub fn iso(self) -> String {
        let secs = self.0.div_euclid(1000);
        let (y, m, d) = civil_from_days(secs.div_euclid(86400));
        let t = secs.rem_euclid(86400);
        format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, m, d, t / 3600, t / 60 % 60, t % 60)
    }

    pub fn plus_days(self, n: i64) -> Date { Date(self.0 + n * 86_400_000) }

    pub fn now() -> Date {
        let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
        Date(t.as_millis() as i64)
    }

    /// `DayKey.key` in UTC. The host turns local time into a key; this is for tests and Linux.
    pub fn utc_key(self) -> String {
        let (y, m, d) = civil_from_days(self.0.div_euclid(86_400_000));
        format(y, m, d)
    }
}

pub fn format(y: i64, m: i64, d: i64) -> String { format!("{:04}-{:02}-{:02}", y, m, d) }

pub fn days_in(year: i64, month: i64) -> i64 {
    match month {
        2 => if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 { 29 } else { 28 },
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

pub fn valid(y: i64, m: i64, d: i64) -> bool {
    (1..=9999).contains(&y) && (1..=12).contains(&m) && d >= 1 && d <= days_in(y, m)
}

pub fn key(y: i64, m: i64, d: i64) -> Option<String> {
    if valid(y, m, d) { Some(format(y, m, d)) } else { None }
}

pub fn parts(k: &str) -> Option<(i64, i64, i64)> {
    let bits: Vec<&str> = k.split('-').filter(|b| !b.is_empty()).collect();
    if bits.len() != 3 || graphemes(bits[0]) != 4 { return None; }
    let (y, m, d) = (bits[0].parse().ok()?, bits[1].parse().ok()?, bits[2].parse().ok()?);
    if valid(y, m, d) { Some((y, m, d)) } else { None }
}

fn day_number(k: &str) -> Option<i64> {
    let (y, m, d) = parts(k)?;
    Some(days_from_civil(y, m, d))
}

pub fn add_days(n: i64, k: &str) -> Option<String> {
    let (y, m, d) = civil_from_days(day_number(k)? + n);
    Some(format(y, m, d))
}

pub fn distance(a: &str, b: &str) -> Option<i64> {
    Some(day_number(b)? - day_number(a)?)
}

/// 0 = Monday ... 6 = Sunday.
pub fn weekday_monday_first(k: &str) -> Option<i64> {
    Some((day_number(k)? + 3).rem_euclid(7))
}

pub const WEEKDAYS: [&str; 7] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
pub const MONTHS: [&str; 12] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

fn short(s: &str) -> &str { &s[..3] }

pub fn short_date(k: &str) -> String {
    match parts(k) {
        Some((_, m, d)) => format!("{} {}", d, short(MONTHS[m as usize - 1])),
        None => k.to_string(),
    }
}

pub fn long_date(k: Option<&str>) -> String {
    let Some(k) = k else { return "Pinned".into() };
    match (parts(k), weekday_monday_first(k)) {
        (Some((y, m, d)), Some(wd)) => format!("{} {} {} {}", short(WEEKDAYS[wd as usize]), d, short(MONTHS[m as usize - 1]), y),
        _ => "Pinned".into(),
    }
}

pub fn medium_date(k: &str) -> String {
    match (parts(k), weekday_monday_first(k)) {
        (Some((_, m, d)), Some(wd)) => format!("{} {} {}", short(WEEKDAYS[wd as usize]), d, short(MONTHS[m as usize - 1])),
        _ => k.to_string(),
    }
}

pub fn group_label(k: &str, today: &str) -> String {
    match distance(k, today) {
        None => k.to_string(),
        Some(0) => "Today".into(),
        Some(1) => "Yesterday".into(),
        Some(-1) => "Tomorrow".into(),
        Some(2..=6) => match weekday_monday_first(k) {
            Some(wd) => WEEKDAYS[wd as usize].to_string(),
            None => medium_date(k),
        },
        Some(_) => medium_date(k),
    }
}

pub fn month_title(y: i64, m: i64) -> String { format!("{} {}", MONTHS[m as usize - 1], y) }

struct Patterns { space: Regex, relative: Regex, iso: Regex, numeric: Regex, day_month: Regex, month_day: Regex }

fn patterns() -> &'static Patterns {
    static P: OnceLock<Patterns> = OnceLock::new();
    P.get_or_init(|| Patterns {
        space: Regex::new(r"\s+").unwrap(),
        relative: Regex::new(r"^([+-])\s?(\d{1,4})$").unwrap(),
        iso: Regex::new(r"^(\d{4})-(\d{1,2})-(\d{1,2})$").unwrap(),
        numeric: Regex::new(r"^(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2}|\d{4}))?$").unwrap(),
        day_month: Regex::new(r"^(\d{1,2})(?:st|nd|rd|th)? ([a-z]+)(?: (\d{4}))?$").unwrap(),
        month_day: Regex::new(r"^([a-z]+) (\d{1,2})(?:st|nd|rd|th)?(?: (\d{4}))?$").unwrap(),
    })
}

fn phrase_year(s: Option<regex::Match>, fallback: i64) -> i64 {
    match s.map(|m| m.as_str()) {
        Some(t) if !t.is_empty() => match t.parse::<i64>() {
            Ok(y) => if t.len() == 2 { 2000 + y } else { y },
            Err(_) => fallback,
        },
        _ => fallback,
    }
}

fn month_named(s: &str) -> Option<i64> {
    if graphemes(s) < 3 { return None; }
    MONTHS.iter().position(|m| m.to_lowercase().starts_with(s)).map(|i| i as i64 + 1)
}

/// DatePhrase.parse.
pub fn parse_phrase(input: &str, today: &str) -> Option<String> {
    let p = patterns();
    let lowered = trim_all(input).to_lowercase();
    let s = p.space.replace_all(&lowered, " ").replace(',', "");
    if s.is_empty() { return None; }
    let (base_year, _, _) = parts(today)?;
    match s.as_str() {
        "today" => return Some(today.to_string()),
        "tomorrow" => return add_days(1, today),
        "yesterday" => return add_days(-1, today),
        _ => {}
    }
    if let Some(m) = p.relative.captures(&s) {
        if let Ok(n) = m[2].parse::<i64>() {
            return add_days(if &m[1] == "-" { -n } else { n }, today);
        }
    }
    if graphemes(&s) >= 3 && s.chars().all(char::is_alphabetic) {
        if let Some(wd) = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].iter().position(|w| w.starts_with(s.as_str())) {
            if let Some(today_wd) = weekday_monday_first(today) {
                return add_days((wd as i64 - today_wd + 7) % 7, today);
            }
        }
    }
    let int = |t: &str| t.parse::<i64>().unwrap_or(0);
    if let Some(m) = p.iso.captures(&s) {
        return key(int(&m[1]), int(&m[2]), int(&m[3]));
    }
    if let Some(m) = p.numeric.captures(&s) {
        return key(phrase_year(m.get(3), base_year), int(&m[2]), int(&m[1]));
    }
    if let Some(m) = p.day_month.captures(&s) {
        if let Some(mon) = month_named(&m[2]) {
            return key(phrase_year(m.get(3), base_year), mon, int(&m[1]));
        }
    }
    if let Some(m) = p.month_day.captures(&s) {
        if let Some(mon) = month_named(&m[1]) {
            return key(phrase_year(m.get(3), base_year), mon, int(&m[2]));
        }
    }
    None
}

/// MonthGrid.weeks.
pub fn month_weeks(year: i64, month: i64) -> Vec<Vec<Option<String>>> {
    let Some(first) = key(year, month, 1) else { return vec![] };
    let Some(lead) = weekday_monday_first(&first) else { return vec![] };
    let mut cells: Vec<Option<String>> = vec![None; lead as usize];
    for d in 1..=days_in(year, month) { cells.push(key(year, month, d)); }
    while cells.len() % 7 != 0 { cells.push(None); }
    cells.chunks(7).map(|w| w.to_vec()).collect()
}

/// MonthGrid.shift.
pub fn month_shift(year: i64, month: i64, delta: i64) -> (i64, i64) {
    let total = year * 12 + (month - 1) + delta;
    (total / 12, total % 12 + 1)
}
