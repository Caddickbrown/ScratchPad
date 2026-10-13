import { describe, expect, it } from "vitest";
import { everythingMarkdown, tableMarkdown, todosMarkdown } from "../markdown";
import { newSheet, type Pad } from "../model";

const s = (o: Partial<Pad>) => newSheet("2026-10-12", { title: "Sprint planning", updatedAt: "2026-10-12T09:00:00Z", ...o });
const t = (text: string, status: "open" | "done" | "deferred") => ({ id: text, text, status, createdAt: "2026-10-12T00:00:00Z" });
const todos = [t("Draft notes", "open"), t("Book dentist", "done"), t("Renew passport", "deferred"), t("  ", "open")];

describe("markdown", () => {
  it("writes the to-do format from the spec", () => {
    expect(todosMarkdown([s({ todos })], { includeDone: false, includeDeferred: true }))
      .toBe("## Sprint planning, Mon 12 Oct 2026\n\n- [ ] Draft notes\n- [ ] Renew passport (deferred)\n");
    expect(todosMarkdown([s({ todos })], { includeDone: true, includeDeferred: false }))
      .toBe("## Sprint planning, Mon 12 Oct 2026\n\n- [ ] Draft notes\n- [x] Book dentist\n");
  });
  it("omits empty sections for every-open-to-do and orders newest first", () => {
    const older = newSheet("2026-10-11", { title: "", todos: [t("Old one", "open")] });
    const empty = newSheet("2026-10-12", { title: "Empty", todos: [t("done", "done")] });
    expect(todosMarkdown([older, s({ todos }), empty], { includeDone: false, includeDeferred: false, openOnly: true }))
      .toBe("## Sprint planning, Mon 12 Oct 2026\n\n- [ ] Draft notes\n\n## Untitled sheet, Sun 11 Oct 2026\n\n- [ ] Old one\n");
  });
  it("renders tables with computed values and escaped pipes", () => {
    expect(tableMarkdown([["A", "B|C"], ["1", "=A2*2"]])).toBe("| A | B\\|C |\n| --- | --- |\n| 1 | 2 |");
  });
  it("renders a whole sheet in reading order", () => {
    const md = everythingMarkdown([s({ tags: ["work"], todos: [t("Ship it", "open")], blocks: [
      { id: "2", kind: "link", x: 0, y: 200, w: 10, url: "https://tauri.app", text: "Tauri" },
      { id: "1", kind: "text", x: 0, y: 0, w: 10, text: "Hello" },
      { id: "3", kind: "image", x: 0, y: 300, w: 10, asset: "assets/x.png", caption: "Board" },
    ] })]);
    expect(md).toBe("# Sprint planning\n\n_Mon 12 Oct 2026 · #work_\n\nHello\n\n[Tauri](https://tauri.app)\n\n![Board](assets/x.png)\n\n## To-do\n\n- [ ] Ship it\n");
  });
});
