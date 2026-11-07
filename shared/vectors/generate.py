#!/usr/bin/env python3
"""Seeded synthetic inputs for the vectors. Writes shared/vectors/inputs.json. Everything here is made
up. Run `swift run core-check record` in apple/ afterwards to record what the Swift code answers."""
import json, random
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
rng = random.Random(20261107)
TODAY = date(2026, 11, 5)
WORDS = ("plan notes review draft ship invoice budget call Priya contract sprint release paste table canvas sheet todo "
         "café naïve Zoë résumé mörk déjà rollover archive sync icloud tauri linux swift rust grid block 🙂 日本語 Ωmega").split()

def sentence(n=8): return " ".join(rng.choice(WORDS) for _ in range(rng.randrange(2, n + 2))).capitalize()

def stamp(d, frac=None):
    t = datetime(d.year, d.month, d.day, rng.randrange(7, 22), rng.randrange(60), rng.randrange(60), tzinfo=timezone.utc)
    s = t.strftime("%Y-%m-%dT%H:%M:%S")
    if frac: s += "." + "".join(rng.choice("0123456789") for _ in range(frac))
    return s + "Z"

def uid():
    h = "0123456789ABCDEF"
    return "".join(rng.choice(h) for _ in range(8)) + "-" + "-".join("".join(rng.choice(h) for _ in range(4)) for _ in range(3)) + "-" + "".join(rng.choice(h) for _ in range(12))

def table(rows, cols):
    out = [[f"Col {c}" for c in range(cols)]]
    for r in range(1, rows):
        row = []
        for c in range(cols):
            k = rng.random()
            if k < .35: row.append(str(rng.randrange(1, 9999)))
            elif k < .5: row.append(f"£{rng.randrange(1, 5000)}.{rng.randrange(100):02d}")
            elif k < .6: row.append(sentence(2))
            elif k < .7 and r > 1: row.append(f"={chr(65 + rng.randrange(cols))}{rng.randrange(1, r + 1)}*{rng.randrange(1, 5)}")
            elif k < .8 and r > 2: row.append(f"=SUM({chr(65 + c)}1:{chr(65 + c)}{r})")
            elif k < .86: row.append(f"=AVG(A1:{chr(65 + rng.randrange(cols))}{max(1, r - 1)})+(2-1)/4")
            elif k < .9: row.append(rng.choice(["=1/0", "=ZZ9", "=FOO(1)", "=1+", "=A1:B2", f"={chr(65 + c)}{r + 1}", "=MAX()", "=COUNT(A1:C3,4,B2)", "=MIN(A1,2)", "  =  1 + 2  ", "=-(-3)", "=1e3+.5", "=sum(a1:b2)", "=AVERAGE(A1:A1)", "=AAAA1", "=(1", "=A0", "=1 2"]))
            else: row.append("")
        out.append(row)
    return out

def block(i, y, assets):
    k = rng.random()
    b = {"id": uid(), "x": rng.randrange(0, 40) * 24, "y": y, "w": rng.randrange(8, 30) * 24, "h": rng.choice([None, None, rng.randrange(2, 20) * 24])}
    if k < .4: b.update(kind="text", text="\n".join(sentence(14) for _ in range(rng.randrange(1, 6))))
    elif k < .55:
        b.update(kind="table", rows=table(rng.randrange(3, 12), rng.randrange(2, 7)), caption=rng.choice(["", sentence(3)]))
        if rng.random() < .5: b["colWidths"] = [120, 90, 200]
    elif k < .65:
        b.update(kind="code", text="let a = 1\n/* path/to \"x\" */\nprint(a)\n")
        if rng.random() < .6: b["language"] = rng.choice(["swift", "rust"])
    elif k < .75: b.update(kind="link", url=f"https://example.test/{rng.choice(WORDS)}?q={i}", text=sentence(4))
    elif k < .85: b.update(kind=rng.choice(["image", "file"]), asset=rng.choice(assets), name="scan.png", size=20000, caption=sentence(3))
    else: b.update(kind="divider")
    if rng.random() < .25: b.update(rotation=rng.choice([15, -7.5, 179.9, 200.25, -180, 45.04, 359.96, 720.5]))
    if rng.random() < .25: b.update(font=rng.choice(["serif", "mono", "hand", "comic"]), fontSize=rng.choice([9, 12, 18, 60]), bold=True, italic=rng.random() < .5)
    return b

def todo(d):
    t = {"id": uid(), "text": rng.choice([sentence(7), sentence(4), "  padded  ", "", "   ", "alpha", "Alpha", "éclair", "zebra", "10 things", "2 things"]),
         "status": rng.choice(["open", "open", "done", "deferred"]), "createdAt": stamp(d - timedelta(days=rng.randrange(6)))}
    t["carriedFrom"] = rng.choice([None, None, f"{d.isoformat()}-aaaaaa"])
    return t

def pad(i, day, assets, frac):
    pid = f"{day.isoformat()}-{''.join(rng.choice('0123456789abcdefghijklmnopqrstuvwxyz') for _ in range(6))}"
    y, blocks = 24, []
    for n in range(rng.randrange(0, 9)):
        blocks.append(block(i * 20 + n, y, assets))
        y += rng.randrange(4, 12) * 24
    return {"v": 2, "id": pid, "date": day.isoformat(), "title": rng.choice(["", sentence(5), "  spaced  "]), "tags": rng.sample(["work", "home", "#Ideas", "ops ", "Writing", "q4", "_x", "--y", "Ünï"], rng.randrange(0, 3)),
            "pinned": False, "createdAt": stamp(day, frac), "updatedAt": stamp(day, frac), "blocks": blocks, "todos": [todo(day) for _ in range(rng.randrange(0, 9))]}

def main():
    assets = [f"assets/{i:04d}-{rng.randrange(1 << 30):x}.png" for i in range(20)]
    sheets, day, n = [], TODAY - timedelta(days=30), 0
    while day <= TODAY:
        for _ in range(rng.choice([1, 1, 1, 2])):
            sheets.append(pad(n, day, assets, rng.choice([None, None, 1, 3, 6, 9])))
            n += 1
        day += timedelta(days=1)
    for i in range(8):
        p = pad(n + i, TODAY, assets, None)
        p.update(id=f"pinned-{i}", date=None, pinned=True, title=f"{sentence(3)} {i}")
        sheets.append(p)
    base = {"id": "odd", "createdAt": "2026-01-02T03:04:05Z", "updatedAt": "2026-01-02T03:04:05Z"}
    blk = {"id": "b", "kind": "text", "x": 0, "y": 0, "w": 96}
    def odd(**kw): return {**base, **kw}
    shapes = [json.dumps(s, ensure_ascii=False) for s in sheets]
    shapes += [json.dumps(s) for s in [
        odd(), odd(v=1, tag="Work", date="2026-01-02"), odd(tag="#Home", tags=["home", "Away"]), odd(date=None), odd(date="2026-01-02", pinned=True),
        odd(updatedAt=None), {k: v for k, v in base.items() if k != "updatedAt"}, odd(title=None, tags=None, blocks=None, todos=None),
        odd(createdAt="2026-02-30T00:00:00Z"), odd(createdAt="2026-01-02T03:04:05+01:00"), odd(createdAt="2026-01-02T03:04:05.5-05:30"), odd(createdAt="2026-01-02 03:04:05Z"), odd(createdAt="nonsense"),
        odd(createdAt="2026-13-02T03:04:05Z"), odd(createdAt="2026-01-02T24:00:00Z"), odd(createdAt="2026-01-02T03:04:60Z"), odd(createdAt=12),
        odd(blocks=[{**blk, "x": 12.0}]), odd(blocks=[{**blk, "x": 12.5}]), odd(blocks=[{**blk, "kind": "sticker"}]), odd(blocks=[{**blk, "font": "comic", "fontSize": 200}]),
        odd(blocks=[{**blk, "font": 3}]), odd(blocks=[{**blk, "rotation": 1e308}]), odd(blocks=[{**blk, "h": None, "bold": None, "italic": None, "fontSize": None, "rotation": None}]),
        odd(blocks=[{**blk, "rows": [["a", 1]]}]), odd(blocks=[{**blk, "colWidths": [10.0, 20]}]), odd(blocks=[{k: v for k, v in blk.items() if k != "w"}]),
        odd(todos=[{"id": "t", "text": "", "status": "open", "createdAt": "2026-01-02T03:04:05Z"}]), odd(todos=[{"id": "t", "status": "open", "createdAt": "2026-01-02T03:04:05Z"}]),
        odd(todos=[{"id": "t", "text": "x", "status": "maybe", "createdAt": "2026-01-02T03:04:05Z"}]), odd(todos=[{"id": "t", "text": "x", "status": "open"}]),
        odd(title='quote " slash / back \\ tab \t nl \n cr \r ff \f bs \b nul \u0000 esc \u001b del \u007f ls   ps   🙂 é'),
        {"createdAt": "2026-01-02T03:04:05Z"}, [], 3, "x", None,
    ]]
    shapes += ["{ not json", ""]
    phrases = []
    for i in range(1200):
        d = TODAY + timedelta(days=rng.randrange(-400, 400))
        phrases.append(rng.choice(["today", "Tomorrow", "yesterday", "mon", "tues", "wednesday", "FRI", "sat", f"+{rng.randrange(40)}", f"- {rng.randrange(40)}", f"-{rng.randrange(9999)}", d.isoformat(), f"{d.day}/{d.month}", f"{d.day}.{d.month}.{d.year}", f"{d.day}/{d.month}/{d.year % 100:02d}",
                                   f"{d.day} {d.strftime('%b').lower()}", f"{d.strftime('%B')} {d.day}", f"{d.day}th {d.strftime('%B')} {d.year}", f"{d.strftime('%b')}, {d.day}  {d.year}", "31 feb", "nonsense", "", "oc 12", "2026-13-01", "sept 1", "1/13", "0/5", "mo", "1st", "29 feb 2028", "  TODAY  ", "+", "١٢", "tuesdayy", "ﬁ", "may 5th", "1th january 2027", "18.3.2027"]))
    pastes = []
    for i in range(400):
        k = rng.randrange(7)
        rows = table(rng.randrange(2, 8), rng.randrange(2, 6))
        if k == 0: pastes.append({"plain": "x", "html": "<meta charset='utf-8'><table class=\"t\"><tbody>" + "".join("<tr>" + "".join(f"<td style=\"a\"><b>{c.replace('&', '&amp;')}</b>&nbsp;</td>" for c in r) + "</tr>" for r in rows) + "</tbody></table>"})
        elif k == 1: pastes.append({"plain": "\n".join("\t".join(c or " " for c in r) for r in rows)})
        elif k == 2: pastes.append({"plain": rng.choice([f"https://example.test/{i}", "http://x.test", "https://a b", "ftp://x.test/y", "http://", "see https://x.test", "HTTPS://UP.TEST/p?q=1#f", "http://[bad", "mailto:a@b.test", "https://user:pw@example.test:8080/a?b#c", "https://exämple.test/", "http://a.test/[x]", "http://a.test/%zz", "https://", "http:example.test", "https:///path", "http://?q", "http://#f", "https://a_b.test/ü"])})
        elif k == 3: pastes.append({"plain": f"```{rng.choice(['swift', '', 'rust '])}\nlet a = {i}\n\n```"})
        elif k == 4: pastes.append({"plain": sentence(30) + "\n" + sentence(10)})
        elif k == 5: pastes.append({"plain": rng.choice(["```no newline```", "``````", "```\n```", "a\tb\r\nc\td", "\t\n\t", "a\tb\nc", "  padded\ttext  \n  x\ty  "])})
        else: pastes.append({"html": rng.choice(["<p>no table</p>", "<TABLE><TR><TD>a<td>b</TR></TABLE>", "<table><tr></tr></table>", "<table><tr><th>A</th></tr><tr><td>1</td><td>2 &lt;3&#39;s&quot;</td></tr></table>", "<table><tr><td>é 🙂</td></tr></table>"]), "plain": rng.choice(["", "   ", "fallback"])})
    titles = ["<html><head><title>  Hello &amp; \n world </title></head>", "<TITLE lang=en>x</TITLE>", "no title here", "<title></title>", "<title>a</title><title>b</title>", "<title>   </title>", "<title>é&nbsp;🙂</title>", "<titled>x</titled>"]
    todo_lists = [[todo(TODAY - timedelta(days=rng.randrange(12))) for _ in range(rng.randrange(2, 40))] for _ in range(30)]
    numbers = ["1,234.50", "£12", "-$3.50%", "+.5", "5.", "1e3", "1e400", "abc", "", " 12 ", "--4", "€-5", "1,2,3", "0x10", "1.2.3", "٣", "+-3", "%5%", "1e", ".", "-.", "1 000"] + [f"{rng.uniform(-1e6, 1e6):.3f}" for _ in range(300)]
    formats = [0, 0.00004, 0.00005, 0.5, 1234.5678, -1234.56785, 1e13, 99999999999999.0, 1e14, 1.5e15, -1e20, 0.1 + 0.2, -0.00001, 1e-10, 999.99995, 0.99995, 1.00005, 1234567.00005] + [rng.uniform(-1e7, 1e7) for _ in range(300)] + [rng.uniform(1e10, 9e13) for _ in range(100)]
    isos = ["2026-11-07T12:30:45Z", "2026-11-07T12:30:45.1Z", "2026-11-07T12:30:45.123Z", "2026-11-07T12:30:45.123456Z", "2026-11-07T12:30:45.123456789Z", "2026-02-30T00:00:00Z", "2026-11-07T12:30:45+01:00", "2026-11-07T12:30:45-0530", "2026-11-07", "bad", "", "2026-11-07T12:30:45", "2026-11-07T12:30Z", "2026-00-07T12:30:45Z", "9999-12-31T23:59:59Z"]
    rotations = [0, 15, -15, 180, -180, 181, 359.96, 720.5, -0.04, 0.05, 179.95, 1e9, -1e9]
    tags = ["  #Work ", "##double", "Q4 plans", "-lead", "_lead", "Ünï", "", "#", "a-b_c", "ÀB", "日本"]
    slugs = [{"title": t, "existing": e} for t, e in [("Plans", []), ("Plans", ["plans"]), ("Plans", ["plans", "plans-2"]), ("Ünï Côde!", []), ("a" * 70, []), ("  --Trim--  ", []), ("x" * 59 + " y", []), ("A/B & C", [])]]
    keys = ["2026-11-05", "2026-11-04", "2026-11-06", "2026-10-30", "2026-10-29", "2026-02-28", "2028-02-29", "2026-02-30", "bad", "2026-1-5", "12026-01-05", "9999-12-31"]
    months = [[2026, 2], [2028, 2], [2026, 11], [2026, 12], [9999, 12]]
    queries = ["", "#work", "PLAN", "café", "2026-11", "example.test", "scan", "col 1", "#", " rust "]
    resizes = [{"corner": c, "dx": dx, "dy": dy, "start": s, "aspect": a} for c in ["topLeft", "topRight", "bottomLeft", "bottomRight"] for dx, dy, s, a in [(24, 12, 100, False), (-500, -500, 100, False), (10.5, 3.5, 0, True), (-30, 40, 240, True)]]
    json.dump({"today": TODAY.isoformat(), "now": "2026-11-05T12:00:00Z", "sheets": shapes, "phrases": phrases, "pastes": pastes, "titles": titles, "todoLists": todo_lists, "numbers": numbers, "formats": formats,
               "isos": isos, "rotations": rotations, "tags": tags, "slugs": slugs, "keys": keys, "months": months, "queries": queries, "resizes": resizes, "snaps": [-13, -12, 0, 11, 12, 13, 35, 36, 1000],
               "widths": [None, 300, 432, 900, 2000]}, open(HERE / "inputs.json", "w"), ensure_ascii=False, indent=0)

main()
