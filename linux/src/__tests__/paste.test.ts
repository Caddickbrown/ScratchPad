import { describe, expect, it } from "vitest";
import { classify, rowsFromHTML, rowsFromTSV } from "../paste";

describe("classify", () => {
  it("plain text becomes text", () => {
    expect(classify({ plain: "hello world" })).toEqual([{ kind: "text", text: "hello world" }]);
  });
  it("a bare URL becomes a link, a URL in prose stays text", () => {
    expect(classify({ plain: "https://tauri.app/docs" })).toEqual([{ kind: "link", url: "https://tauri.app/docs" }]);
    expect(classify({ plain: "see https://tauri.app" })[0].kind).toBe("text");
  });
  it("TSV becomes a table", () => {
    expect(classify({ plain: "Item\tStatus\nDrag\tDone" })).toEqual([{ kind: "table", rows: [["Item", "Status"], ["Drag", "Done"]] }]);
  });
  it("an HTML table wins over its plain fallback", () => {
    const html = "<table><tr><th>A</th><th>B</th></tr><tr><td>1 &amp; 2</td><td><b>3</b></td></tr></table>";
    expect(classify({ plain: "A B", html })).toEqual([{ kind: "table", rows: [["A", "B"], ["1 & 2", "3"]] }]);
  });
  it("fenced code becomes code", () => {
    expect(classify({ plain: "```ts\nlet a = 1\n```" })).toEqual([{ kind: "code", text: "let a = 1", language: "ts" }]);
  });
  it("files win over text, images by extension or mime", () => {
    const r = classify({ plain: "x", files: [{ name: "shot.PNG" }, { name: "plan.pdf" }, { name: "blob", type: "image/webp" }] });
    expect(r.map((x) => x.kind)).toEqual(["image", "file", "image"]);
  });
});

describe("parsers", () => {
  it("rejects ragged TSV", () => {
    expect(rowsFromTSV("a\tb\nc")).toBeUndefined();
  });
  it("pads ragged HTML rows", () => {
    expect(rowsFromHTML("<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>")).toEqual([["a", "b"], ["c", ""]]);
  });
});
