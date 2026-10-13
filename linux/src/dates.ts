// Typed date phrases for the date picker, docs/v0.2-spec.md section 2.
import { dayKey, parseDay } from "./model";

const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];

const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const valid = (y: number, m: number, d: number) => { const x = new Date(y, m, d); return x.getMonth() === m && x.getDate() === d ? x : null; };
const month = (s: string) => { const i = MONTHS.findIndex((m) => s.length >= 3 && m.startsWith(s)); return i; };

/** Returns YYYY-MM-DD or null. `today` is the reference day key. */
export function parsePhrase(input: string, today = dayKey()): string | null {
  const s = input.trim().toLowerCase().replace(/\s+/g, " ");
  if (!s) return null;
  const base = parseDay(today);
  if (s === "today") return today;
  if (s === "tomorrow") return dayKey(addDays(base, 1));
  if (s === "yesterday") return dayKey(addDays(base, -1));
  let m = /^([+-])(\d{1,3})$/.exec(s);
  if (m) return dayKey(addDays(base, (m[1] === "-" ? -1 : 1) * Number(m[2])));
  const wd = WEEKDAYS.findIndex((w) => s.length >= 3 && w.startsWith(s));
  if (wd >= 0) return dayKey(addDays(base, (wd - base.getDay() + 7) % 7));
  m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s);
  if (m) { const d = valid(+m[1], +m[2] - 1, +m[3]); return d ? dayKey(d) : null; }
  m = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?$/.exec(s);
  if (m) {
    const y = m[3] ? (m[3].length === 2 ? 2000 + +m[3] : +m[3]) : base.getFullYear();
    const d = valid(y, +m[2] - 1, +m[1]); return d ? dayKey(d) : null;
  }
  m = /^(\d{1,2}) ([a-z]+)(?: (\d{4}))?$/.exec(s) ?? null;
  let day: number | null = null, mon = -1, year: number | null = null;
  if (m) { day = +m[1]; mon = month(m[2]); year = m[3] ? +m[3] : null; }
  else {
    const n = /^([a-z]+) (\d{1,2})(?: (\d{4}))?$/.exec(s);
    if (n) { day = +n[2]; mon = month(n[1]); year = n[3] ? +n[3] : null; }
  }
  if (day !== null && mon >= 0) { const d = valid(year ?? base.getFullYear(), mon, day); return d ? dayKey(d) : null; }
  return null;
}

/** Month grid for the picker: weeks of 7 (Monday first), null outside the month. */
export function monthGrid(year: number, monthIndex: number): (string | null)[][] {
  const first = new Date(year, monthIndex, 1);
  const lead = (first.getDay() + 6) % 7;
  const days = new Date(year, monthIndex + 1, 0).getDate();
  const cells: (string | null)[] = Array(lead).fill(null);
  for (let d = 1; d <= days; d++) cells.push(dayKey(new Date(year, monthIndex, d)));
  while (cells.length % 7) cells.push(null);
  const weeks: (string | null)[][] = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return weeks;
}
