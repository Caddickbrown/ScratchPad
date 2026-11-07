//! Formula.swift: cell values, the parser and the evaluator.
use crate::text::{trim_all, trim_ws};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FormulaError { Ref, Div0, Cycle, Err }

impl FormulaError {
    pub fn text(self) -> &'static str {
        match self { FormulaError::Ref => "#REF!", FormulaError::Div0 => "#DIV/0!", FormulaError::Cycle => "#CYCLE!", FormulaError::Err => "#ERR!" }
    }
}

#[derive(Clone, PartialEq, Debug)]
pub enum CellValue { Empty, Number(f64), Text(String), Error(FormulaError) }

impl CellValue {
    pub fn display(&self) -> String {
        match self {
            CellValue::Empty => String::new(),
            CellValue::Number(n) => format_number(*n),
            CellValue::Text(s) => s.clone(),
            CellValue::Error(e) => e.text().to_string(),
        }
    }
    fn number(&self) -> Option<f64> { if let CellValue::Number(n) = self { Some(*n) } else { None } }
}

pub fn is_formula(raw: &str) -> bool { trim_ws(raw).starts_with('=') }

pub fn column_name(index: usize) -> String {
    let mut s = Vec::new();
    let mut n = index + 1;
    while n > 0 {
        let r = (n - 1) % 26;
        s.push(b'A' + r as u8);
        n = (n - 1) / 26;
    }
    s.reverse();
    String::from_utf8(s).unwrap()
}

pub fn column_index(name: &str) -> Option<usize> {
    let mut n = 0usize;
    for ch in name.to_uppercase().chars() {
        if !ch.is_ascii_uppercase() { return None; }
        n = n * 26 + (ch as usize - 64);
    }
    if n == 0 { None } else { Some(n - 1) }
}

pub fn address(row: usize, col: usize) -> String { format!("{}{}", column_name(col), row + 1) }

fn plain_number(s: &str) -> bool {
    let b = s.as_bytes();
    let mut i = 0;
    let digits = |i: &mut usize| { let st = *i; while *i < b.len() && b[*i].is_ascii_digit() { *i += 1; } *i - st };
    let lead = digits(&mut i);
    if lead > 0 {
        if i < b.len() && b[i] == b'.' { i += 1; digits(&mut i); }
    } else {
        if i >= b.len() || b[i] != b'.' { return false; }
        i += 1;
        if digits(&mut i) == 0 { return false; }
    }
    if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
        i += 1;
        if i < b.len() && (b[i] == b'-' || b[i] == b'+') { i += 1; }
        if digits(&mut i) == 0 { return false; }
    }
    i == b.len()
}

/// Formula.parseNumber.
pub fn parse_number(raw: &str) -> Option<f64> {
    let marks = ['£', '$', '€', '%'];
    let mut s = trim_all(raw);
    let mut neg = false;
    if s.starts_with('-') || s.starts_with('+') { neg = s.starts_with('-'); s = &s[1..]; }
    s = s.trim_start_matches(marks).trim_end_matches(marks);
    let joined = s.replace(',', "");
    let mut t = trim_ws(&joined);
    if !neg && (t.starts_with('-') || t.starts_with('+')) { neg = t.starts_with('-'); t = &t[1..]; }
    if t.is_empty() || !plain_number(t) { return None; }
    let v: f64 = t.parse().ok()?;
    if !v.is_finite() { return None; }
    Some(if neg { -v } else { v })
}

fn grouped(digits: &str) -> String {
    let mut out: Vec<char> = Vec::with_capacity(digits.len() + digits.len() / 3);
    for (i, c) in digits.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 { out.push(','); }
        out.push(c);
    }
    out.iter().rev().collect()
}

/// Formula.format.
pub fn format_number(value: f64) -> String {
    if !value.is_finite() { return FormulaError::Err.text().to_string(); }
    let magnitude = value.abs();
    let mut int_string;
    let mut frac = String::new();
    if magnitude < 1e14 {
        // The whole part stays out of the multiply: at this size it would leave float dust behind.
        let mut whole = magnitude as i64;
        let mut units = ((magnitude - whole as f64) * 10_000.0).round() as i64;
        if units == 10_000 { whole += 1; units = 0; }
        int_string = whole.to_string();
        frac = format!("{:04}", units);
        while frac.ends_with('0') { frac.pop(); }
    } else {
        int_string = format!("{:.0}", magnitude);
    }
    if int_string.len() >= 4 { int_string = grouped(&int_string); }
    let body = if frac.is_empty() { int_string } else { format!("{}.{}", int_string, frac) };
    if value < 0.0 && body != "0" { format!("-{}", body) } else { body }
}

#[derive(Clone, PartialEq, Debug)]
enum Token { Number(f64), Ref(i64, i64), Ident(String), Op(char) }

fn tokenize(src: &str) -> Result<Vec<Token>, FormulaError> {
    let chars: Vec<char> = src.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    let digit = |c: char| c.is_ascii_digit();
    let letter = |c: char| c.is_ascii_alphabetic();
    while i < chars.len() {
        let ch = chars[i];
        if ch.is_whitespace() { i += 1; continue; }
        if digit(ch) || ch == '.' {
            let (mut j, mut seen_dot) = (i, false);
            while j < chars.len() && (digit(chars[j]) || (chars[j] == '.' && !seen_dot)) {
                if chars[j] == '.' { seen_dot = true; }
                j += 1;
            }
            if j < chars.len() && (chars[j] == 'e' || chars[j] == 'E') {
                let mut k = j + 1;
                if k < chars.len() && (chars[k] == '+' || chars[k] == '-') { k += 1; }
                if k < chars.len() && digit(chars[k]) {
                    while k < chars.len() && digit(chars[k]) { k += 1; }
                    j = k;
                }
            }
            let text: String = chars[i..j].iter().collect();
            let v: f64 = if text == "." { return Err(FormulaError::Err) } else { text.parse().map_err(|_| FormulaError::Err)? };
            out.push(Token::Number(v));
            i = j;
            continue;
        }
        if letter(ch) {
            let mut j = i;
            while j < chars.len() && letter(chars[j]) { j += 1; }
            let letters: String = chars[i..j].iter().collect();
            let mut k = j;
            while k < chars.len() && digit(chars[k]) { k += 1; }
            if k > j {
                if letters.len() > 3 { return Err(FormulaError::Err); }
                let col = column_index(&letters).ok_or(FormulaError::Err)?;
                let row: i64 = chars[j..k].iter().collect::<String>().parse().map_err(|_| FormulaError::Err)?;
                out.push(Token::Ref(row - 1, col as i64));
            } else {
                out.push(Token::Ident(letters.to_uppercase()));
            }
            i = k;
            continue;
        }
        if "+-*/(),:".contains(ch) { out.push(Token::Op(ch)); i += 1; continue; }
        return Err(FormulaError::Err);
    }
    Ok(out)
}

/// Evaluates every cell of a table. Row 1 is the first row, column A the first column.
pub struct TableEvaluator<'a> {
    rows: &'a [Vec<String>],
    pub column_count: usize,
    memo: Vec<Option<CellValue>>,
    visiting: Vec<bool>,
}

impl<'a> TableEvaluator<'a> {
    pub fn new(rows: &'a [Vec<String>]) -> TableEvaluator<'a> {
        let column_count = rows.iter().map(|r| r.len()).max().unwrap_or(0);
        let n = rows.len() * column_count;
        TableEvaluator { rows, column_count, memo: vec![None; n], visiting: vec![false; n] }
    }

    fn raw(&self, r: usize, c: usize) -> &'a str {
        self.rows.get(r).and_then(|row| row.get(c)).map(|s| s.as_str()).unwrap_or("")
    }

    pub fn value(&mut self, r: usize, c: usize) -> CellValue {
        self.cell(r as i64, c as i64).unwrap_or(CellValue::Error(FormulaError::Ref))
    }

    pub fn display(&mut self, r: usize, c: usize) -> String { self.value(r, c).display() }

    pub fn evaluate_all(&mut self) -> Vec<Vec<CellValue>> {
        let rows = self.rows;
        rows.iter().enumerate().map(|(r, row)| (0..row.len()).map(|c| self.value(r, c)).collect()).collect()
    }

    fn cell(&mut self, r: i64, c: i64) -> Result<CellValue, FormulaError> {
        if r < 0 || c < 0 || r as usize >= self.rows.len() || c as usize >= self.column_count { return Err(FormulaError::Ref); }
        let (ru, cu) = (r as usize, c as usize);
        let k = ru * self.column_count + cu;
        if let Some(v) = &self.memo[k] { return Ok(v.clone()); }
        if self.visiting[k] { return Err(FormulaError::Cycle); }
        let raw = self.raw(ru, cu);
        let trimmed = trim_ws(raw);
        let v = if let Some(source) = trimmed.strip_prefix('=') {
            self.visiting[k] = true;
            let result = tokenize(source).and_then(|tokens| Parser { tokens, table: self, p: 0 }.run());
            self.visiting[k] = false;
            match result { Ok(n) => CellValue::Number(n), Err(e) => CellValue::Error(e) }
        } else if trimmed.is_empty() {
            CellValue::Empty
        } else if let Some(n) = parse_number(raw) {
            CellValue::Number(n)
        } else {
            CellValue::Text(raw.to_string())
        };
        self.memo[k] = Some(v.clone());
        Ok(v)
    }
}

struct Parser<'t, 'a> { tokens: Vec<Token>, table: &'t mut TableEvaluator<'a>, p: usize }

impl Parser<'_, '_> {
    fn run(mut self) -> Result<f64, FormulaError> {
        let v = self.expr()?;
        if self.p != self.tokens.len() || !v.is_finite() { return Err(FormulaError::Err); }
        Ok(v)
    }

    fn peek(&self) -> Option<&Token> { self.tokens.get(self.p) }

    fn eat(&mut self, c: char) -> bool {
        if self.peek() == Some(&Token::Op(c)) { self.p += 1; true } else { false }
    }

    fn expr(&mut self) -> Result<f64, FormulaError> {
        let mut v = self.term()?;
        loop {
            if self.eat('+') { v += self.term()?; } else if self.eat('-') { v -= self.term()?; } else { return Ok(v); }
        }
    }

    fn term(&mut self) -> Result<f64, FormulaError> {
        let mut v = self.unary()?;
        loop {
            if self.eat('*') {
                v *= self.unary()?;
            } else if self.eat('/') {
                let d = self.unary()?;
                if d == 0.0 { return Err(FormulaError::Div0); }
                v /= d;
            } else {
                return Ok(v);
            }
        }
    }

    fn unary(&mut self) -> Result<f64, FormulaError> {
        if self.eat('-') { return Ok(-self.unary()?); }
        if self.eat('+') { return self.unary(); }
        self.primary()
    }

    fn primary(&mut self) -> Result<f64, FormulaError> {
        match self.peek().cloned() {
            None => Err(FormulaError::Err),
            Some(Token::Number(v)) => { self.p += 1; Ok(v) }
            Some(Token::Ref(r, c)) => {
                self.p += 1;
                if self.peek() == Some(&Token::Op(':')) { return Err(FormulaError::Err); }
                match self.table.cell(r, c)? {
                    CellValue::Number(n) => Ok(n),
                    CellValue::Error(e) => Err(e),
                    CellValue::Empty | CellValue::Text(_) => Ok(0.0),
                }
            }
            Some(Token::Op('(')) => {
                self.p += 1;
                let v = self.expr()?;
                if !self.eat(')') { return Err(FormulaError::Err); }
                Ok(v)
            }
            Some(Token::Ident(name)) => {
                if !["SUM", "AVG", "AVERAGE", "MIN", "MAX", "COUNT"].contains(&name.as_str()) { return Err(FormulaError::Err); }
                self.p += 1;
                self.call(&name)
            }
            Some(_) => Err(FormulaError::Err),
        }
    }

    fn call(&mut self, name: &str) -> Result<f64, FormulaError> {
        if !self.eat('(') { return Err(FormulaError::Err); }
        let mut values = Vec::new();
        if !self.eat(')') {
            loop {
                values.extend(self.argument()?);
                if !self.eat(',') { break; }
            }
            if !self.eat(')') { return Err(FormulaError::Err); }
        }
        for v in &values {
            if let CellValue::Error(e) = v { return Err(*e); }
        }
        let nums: Vec<f64> = values.iter().filter_map(CellValue::number).collect();
        match name {
            "SUM" => Ok(nums.iter().fold(0.0, |a, b| a + b)),
            "AVG" | "AVERAGE" => {
                if nums.is_empty() { return Err(FormulaError::Div0); }
                Ok(nums.iter().fold(0.0, |a, b| a + b) / nums.len() as f64)
            }
            "MIN" => Ok(nums.iter().copied().reduce(f64::min).unwrap_or(0.0)),
            "MAX" => Ok(nums.iter().copied().reduce(f64::max).unwrap_or(0.0)),
            "COUNT" => Ok(nums.len() as f64),
            _ => Err(FormulaError::Err),
        }
    }

    fn argument(&mut self) -> Result<Vec<CellValue>, FormulaError> {
        if let Some(&Token::Ref(r1, c1)) = self.peek() {
            let next = self.tokens.get(self.p + 1).cloned();
            if next == Some(Token::Op(':')) {
                let Some(&Token::Ref(r2, c2)) = self.tokens.get(self.p + 2) else { return Err(FormulaError::Err) };
                self.p += 3;
                let mut out = Vec::new();
                for r in r1.min(r2)..=r1.max(r2) {
                    for c in c1.min(c2)..=c1.max(c2) { out.push(self.table.cell(r, c)?); }
                }
                return Ok(out);
            }
            if next.is_none() || next == Some(Token::Op(',')) || next == Some(Token::Op(')')) {
                self.p += 1;
                return Ok(vec![self.table.cell(r1, c1)?]);
            }
        }
        Ok(vec![CellValue::Number(self.expr()?)])
    }
}
