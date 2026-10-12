// Components board, left column: the clipboard type picks the block. Same order as PasteClassifier.swift.

export interface ClipboardContents {
  plain?: string;
  html?: string;
  files?: { name: string; path?: string; bytes?: ArrayBuffer; type?: string }[];
}

export type PasteResult =
  | { kind: "text"; text: string }
  | { kind: "code"; text: string; language?: string }
  | { kind: "link"; url: string; title?: string }
  | { kind: "table"; rows: string[][] }
  | { kind: "image"; file: NonNullable<ClipboardContents["files"]>[number]; ext: string }
  | { kind: "file"; file: NonNullable<ClipboardContents["files"]>[number] };

export const IMAGE_EXT = new Set(["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"]);

export function classify(c: ClipboardContents): PasteResult[] {
  if (c.files && c.files.length) {
    return c.files.map((f) => {
      const ext = extOf(f.name) || (f.type?.startsWith("image/") ? f.type.slice(6) : "");
      return IMAGE_EXT.has(ext) || f.type?.startsWith("image/") ? { kind: "image", file: f, ext: ext || "png" } : { kind: "file", file: f };
    });
  }
  if (c.html) {
    const rows = rowsFromHTML(c.html);
    if (rows) return [{ kind: "table", rows }];
  }
  const plain = (c.plain ?? "").trim();
  if (!plain) return [];
  const tsv = rowsFromTSV(plain);
  if (tsv) return [{ kind: "table", rows: tsv }];
  const url = singleURL(plain);
  if (url) return [{ kind: "link", url }];
  const fenced = fencedCode(plain);
  if (fenced) return [{ kind: "code", text: fenced.body, language: fenced.lang }];
  return [{ kind: "text", text: plain }];
}

export const extOf = (name: string): string => {
  const i = name.lastIndexOf(".");
  return i < 0 ? "" : name.slice(i + 1).toLowerCase();
};

export function singleURL(s: string): string | undefined {
  if (/\s/.test(s)) return undefined;
  try {
    const u = new URL(s);
    return (u.protocol === "http:" || u.protocol === "https:") && u.host ? s : undefined;
  } catch {
    return undefined;
  }
}

export function fencedCode(s: string): { body: string; lang?: string } | undefined {
  if (!s.startsWith("```") || !s.endsWith("```") || s.length <= 6) return undefined;
  const inner = s.slice(3, -3);
  const nl = inner.indexOf("\n");
  if (nl < 0) return undefined;
  const lang = inner.slice(0, nl).trim();
  return { body: inner.slice(nl + 1).replace(/^\n+|\n+$/g, ""), lang: lang || undefined };
}

/** Tab-separated text with at least two rows and a consistent column count is a table. */
export function rowsFromTSV(s: string): string[][] | undefined {
  const lines = s.split("\n");
  if (lines.length < 2 || !lines.every((l) => l.includes("\t"))) return undefined;
  const rows = lines.map((l) => l.split("\t").map((c) => c.trim()));
  const cols = rows[0].length;
  if (cols < 2 || !rows.every((r) => r.length === cols)) return undefined;
  return rows;
}

/** First <table>: each <tr>, each <td>/<th>, tags stripped, common entities decoded. */
export function rowsFromHTML(html: string): string[][] | undefined {
  const table = html.match(/<table\b[\s\S]*?<\/table>/i)?.[0];
  if (!table) return undefined;
  const rows: string[][] = [];
  for (const tr of table.match(/<tr\b[\s\S]*?<\/tr>/gi) ?? []) {
    const cells = [...tr.matchAll(/<t[dh]\b[^>]*>([\s\S]*?)<\/t[dh]>/gi)].map((m) => decode(m[1].replace(/<[^>]+>/g, "")).trim());
    if (cells.length) rows.push(cells);
  }
  if (!rows.length) return undefined;
  const cols = Math.max(...rows.map((r) => r.length));
  return rows.map((r) => [...r, ...Array(cols - r.length).fill("")]);
}

const decode = (s: string) =>
  s.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'");

/** Browser DataTransfer (paste or drop) to ClipboardContents. File bytes are read lazily by the caller. */
export function fromDataTransfer(dt: DataTransfer): ClipboardContents {
  const files = Array.from(dt.files ?? []).map((f) => ({ name: f.name || `pasted.${f.type.split("/")[1] ?? "bin"}`, type: f.type, blob: f }));
  const uris = dt.getData("text/uri-list");
  const fileURIs = uris ? uris.split(/\r?\n/).filter((u) => u.startsWith("file://")) : [];
  if (!files.length && fileURIs.length) {
    return { files: fileURIs.map((u) => ({ name: decodeURIComponent(u.split("/").pop() ?? "file"), path: decodeURIComponent(u.replace(/^file:\/\//, "")) })) };
  }
  return { plain: dt.getData("text/plain") || undefined, html: dt.getData("text/html") || undefined, files: files.length ? (files as any) : undefined };
}
