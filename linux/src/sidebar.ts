// The rail: By day / By tag, tag sort, pinned sheets. Rows are drop targets for dragged to-dos.
import { groupByDay, groupByTag, type Group, type Pad, type TagSort } from "./model";
import { prefs, setPref } from "./prefs";
import { deleteSheet, openPad, state } from "./state";
import { $, el, I, menu, segmented } from "./ui";

const titleOf = (p: Pad) => p.title.trim() || "Untitled sheet";

function row(p: Pad, side: string): HTMLElement {
  const active = state.current?.id === p.id;
  const shown = active ? state.current! : p;
  const b = el("button", { class: `item${active ? " active" : ""}`, "data-sheet-id": p.id, "aria-current": active ? "page" : null,
    onClick: () => openPad(p.id) },
    el("span", { class: "name" }, titleOf(shown)), el("span", { class: "when" }, side));
  b.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    menu([{ label: "Open", run: () => openPad(p.id) }, "sep", { label: "Delete sheet", danger: true, icon: I.trash, run: () => deleteSheet(p.id) }], { x: e.clientX, y: e.clientY });
  });
  return b;
}

function group(g: Group, side: (p: Pad) => string): HTMLElement {
  return el("section", { class: "group" },
    el("h3", { class: g.label.startsWith("#") ? "tag" : "" }, el("span", {}, g.label), el("span", { class: "meta" }, g.meta)),
    el("div", { class: "list" }, ...g.sheets.map((p) => row(p, side(p)))));
}

export function renderRail(): void {
  const rail = $(".rail");
  if (!rail) return;
  const pads = state.pads.map((p) => (p.id === state.current?.id ? state.current! : p));
  const byTag = prefs.groupBy === "tag";
  const groups = byTag ? groupByTag(pads, prefs.tagSort) : groupByDay(pads);
  const pinned = pads.filter((p) => p.pinned);

  const sortSel = el("label", { class: "sortline" }, "Sort tags",
    el("select", { "aria-label": "Sort tags", onChange: (e: Event) => { setPref("tagSort", (e.target as HTMLSelectElement).value as TagSort); renderRail(); } },
      ...[["az", "A to Z"], ["count", "Most sheets"], ["recent", "Recently used"]].map(([v, l]) => el("option", { value: v, selected: prefs.tagSort === v ? true : null }, l))));

  const scrollTop = rail.querySelector(".groups")?.scrollTop ?? 0;
  rail.replaceChildren(...[
    segmented("Group sheets by", [{ value: "day", label: "By day" }, { value: "tag", label: "By tag" }], prefs.groupBy, (v) => { setPref("groupBy", v); renderRail(); }),
    byTag ? sortSel : null,
    el("div", { class: "groups" },
      ...groups.map((g) => group(g, (p) => (byTag ? shortOf(p) : p.tags[0] ? `#${p.tags[0]}` : ""))),
      !groups.length ? el("p", { class: "none" }, byTag ? "No tags yet. Add one from the sheet header." : "No sheets yet.") : null),
    !byTag && pinned.length ? group({ key: "pinned", label: "Pinned", meta: "", sheets: pinned }, (p) => (p.tags[0] ? `#${p.tags[0]}` : "")) : null,
  ].filter((x): x is HTMLElement => !!x));
  const groupsEl = rail.querySelector(".groups");
  if (groupsEl) groupsEl.scrollTop = scrollTop;
}

function shortOf(p: Pad): string {
  if (!p.date) return "Pinned";
  const [, m, d] = p.date.split("-").map(Number);
  return `${d} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1]}`;
}
