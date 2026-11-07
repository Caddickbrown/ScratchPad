//! Foundation's string behaviour where it decides an answer.
use std::cmp::Ordering;
use unicode_segmentation::UnicodeSegmentation;

/// CharacterSet.whitespaces: Zs and tab.
pub fn is_ws(c: char) -> bool {
    matches!(c, '\t' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'..='\u{200a}' | '\u{202f}' | '\u{205f}' | '\u{3000}')
}

/// CharacterSet.newlines.
pub fn is_nl(c: char) -> bool {
    matches!(c, '\n' | '\x0b' | '\x0c' | '\r' | '\u{85}' | '\u{2028}' | '\u{2029}')
}

pub fn trim_ws(s: &str) -> &str { s.trim_matches(is_ws) }
pub fn trim_nl(s: &str) -> &str { s.trim_matches(is_nl) }
pub fn trim_all(s: &str) -> &str { s.trim_matches(|c| is_ws(c) || is_nl(c)) }

/// `String.count`.
pub fn graphemes(s: &str) -> usize {
    if s.is_ascii() && !s.contains('\r') { s.len() } else { s.graphemes(true).count() }
}

/// `String(s.prefix(n))`.
pub fn prefix(s: &str, n: usize) -> String {
    s.graphemes(true).take(n).collect()
}

/// Split on `Character.isNewline`, dropping empties, with CRLF as one separator.
pub fn lines(s: &str) -> impl Iterator<Item = &str> {
    s.split(is_nl).filter(|l| !l.is_empty())
}

/// `split(separator: "\n", omittingEmptySubsequences: false)`: CRLF is one Character, not a split.
pub fn split_lf(s: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let b = s.as_bytes();
    for i in 0..b.len() {
        if b[i] == b'\n' && (i == 0 || b[i - 1] != b'\r') {
            out.push(&s[start..i]);
            start = i + 1;
        }
    }
    out.push(&s[start..]);
    out
}

fn fold(c: char) -> (char, u8) {
    let lower = c.to_lowercase().next().unwrap_or(c);
    match lower {
        'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' => ('a', 1),
        'ç' => ('c', 1),
        'è' | 'é' | 'ê' | 'ë' => ('e', 1),
        'ì' | 'í' | 'î' | 'ï' => ('i', 1),
        'ñ' => ('n', 1),
        'ò' | 'ó' | 'ô' | 'õ' | 'ö' => ('o', 1),
        'ù' | 'ú' | 'û' | 'ü' => ('u', 1),
        'ý' | 'ÿ' => ('y', 1),
        other => (other, 0),
    }
}

fn class(c: char) -> u8 {
    if c.is_whitespace() { 0 } else if c.is_alphabetic() { 3 } else if c.is_numeric() { 2 } else { 1 }
}

/// Approximates localizedCaseInsensitiveCompare: whitespace, punctuation, digits,
/// letters, accents as a tie-break. Not full ICU collation.
pub fn localized_cmp(a: &str, b: &str) -> Ordering {
    let mut accent = Ordering::Equal;
    let (mut ia, mut ib) = (a.chars(), b.chars());
    loop {
        match (ia.next(), ib.next()) {
            (None, None) => return accent,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) => {
                let (fx, ax) = fold(x);
                let (fy, ay) = fold(y);
                let primary = (class(fx), fx).cmp(&(class(fy), fy));
                if primary != Ordering::Equal { return primary; }
                if accent == Ordering::Equal { accent = ax.cmp(&ay); }
            }
        }
    }
}
