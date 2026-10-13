// Sheet header: DATE box with picker, title, tag chips with suggestions.
import { monthGrid, parsePhrase } from "./dates";
import { dayKey, longDate, normalizeTag, parseDay, tagCounts, todayKey } from "./model";
import { cur, moveSheetTo, newSheetOn, state, touch, view } from "./state";
import { closePopover, el, I, popover } from "./ui";

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

/** Month grid picker. `mode` move: changes the current sheet's date; create: makes a new sheet on the picked date. */
export function openDatePicker(anchor: HTMLElement, mode: "move" | "create"): void {
  const pad = state.current;
  const start = mode === "move" && pad?.date ? pad.date : todayKey();
  let shown = parseDay(start);
  let picked = start;
  const withSheets = new Set(state.pads.map((p) => p.date).filter(Boolean) as string[]);

  const box = el("div", { class: "datepicker", role: "dialog", "aria-label": mode === "move" ? "Change date" : "New sheet on a date" });
  const typed = el("input", { class: "typed", placeholder: "Type: fri, 15 oct, +3", "aria-label": "Type a date" }) as HTMLInputElement;
  const confirm = el("button", { class: "primary small" });
  const grid = el("div", { class: "grid" });
  const title = el("span", { class: "month" });

  const label = () => {
    const d = parseDay(picked);
    confirm.textContent = picked === pad?.date && mode === "move" ? "Keep date" : `${mode === "move" ? "Move to" : "Create on"} ${d.getDate()} ${MONTHS[d.getMonth()].slice(0, 3)}`;
  };
  const draw = () => {
    title.textContent = `${MONTHS[shown.getMonth()]} ${shown.getFullYear()}`;
    grid.replaceChildren(...["M", "T", "W", "T", "F", "S", "S"].map((d) => el("span", { class: "dow", "aria-hidden": "true" }, d)));
    for (const key of monthGrid(shown.getFullYear(), shown.getMonth()).flat()) {
      if (!key) { grid.append(el("span", { class: "pad" })); continue; }
      const n = Number(key.slice(8));
      grid.append(el("button", {
        class: ["day", key === todayKey() ? "today" : "", key === picked ? "picked" : "", withSheets.has(key) ? "has" : ""].join(" "),
        "aria-label": `${n} ${MONTHS[shown.getMonth()]}${withSheets.has(key) ? ", has sheets" : ""}`, "aria-pressed": String(key === picked),
        onClick: () => { picked = key; draw(); label(); },
        onDblclick: () => { picked = key; commit(); },
      }, String(n)));
    }
  };
  const commit = async () => {
    close();
    if (mode === "create") await newSheetOn(picked);
    else if (picked !== pad?.date) await moveSheetTo(picked);
  };
  typed.addEventListener("input", () => {
    const k = parsePhrase(typed.value);
    typed.classList.toggle("bad", !!typed.value.trim() && !k);
    if (k) { picked = k; shown = parseDay(k); draw(); label(); }
  });
  typed.addEventListener("keydown", (e) => { if (e.key === "Enter" && parsePhrase(typed.value)) commit(); });
  confirm.addEventListener("click", commit);

  box.append(
    typed,
    el("div", { class: "nav" },
      el("button", { class: "icon-btn", "aria-label": "Previous month", html: I.left, onClick: () => { shown = new Date(shown.getFullYear(), shown.getMonth() - 1, 1); draw(); } }),
      title,
      el("button", { class: "icon-btn", "aria-label": "Next month", html: I.right, onClick: () => { shown = new Date(shown.getFullYear(), shown.getMonth() + 1, 1); draw(); } })),
    grid,
    el("div", { class: "foot" },
      el("button", { class: "link", onClick: () => { picked = todayKey(); shown = parseDay(picked); draw(); label(); } }, "Today"),
      el("span", { class: "spacer" }),
      el("button", { class: "ghost small", onClick: () => close() }, "Cancel"),
      confirm));
  draw(); label();
  const close = popover(box, anchor);
  typed.focus();
}

function chip(tag: string): HTMLElement {
  return el("span", { class: "chip" }, `#${tag}`,
    el("button", { "aria-label": `Remove tag ${tag}`, html: I.x, onClick: () => {
      cur().tags = cur().tags.filter((t) => t !== tag); touch(); renderHeader(); view.rail();
    } }));
}

function addTag(raw: string): void {
  const t = normalizeTag(raw);
  if (!t || cur().tags.includes(t)) return;
  cur().tags.push(t);
  touch();
  view.rail();
}

function openTagInput(btn: HTMLElement): void {
  const input = el("input", { class: "tag-input", "aria-label": "Add tag", placeholder: "tag" }) as HTMLInputElement;
  const wrap = el("label", { class: "chip editing" }, "#", input);
  btn.replaceWith(wrap);
  input.focus();
  let closeSugg = () => {};
  const suggest = () => {
    const q = normalizeTag(input.value);
    const all = tagCounts(state.pads).filter((x) => !cur().tags.includes(x.tag) && (!q || x.tag.startsWith(q))).slice(0, 6);
    const list = el("div", { class: "menu", role: "listbox", "aria-label": "Tag suggestions" },
      ...all.map((x) => el("button", { role: "option", onPointerdown: (e: Event) => e.preventDefault(), onClick: () => { addTag(x.tag); input.value = ""; renderHeader(); } },
        el("span", { class: "label mono" }, `#${x.tag}`), el("span", { class: "key" }, `${x.count} sheet${x.count === 1 ? "" : "s"}`))),
      q && !all.some((x) => x.tag === q) ? el("button", { role: "option", class: "create", onPointerdown: (e: Event) => e.preventDefault(), onClick: () => { addTag(q); renderHeader(); } }, `Create #${q}`) : null);
    closeSugg();
    if (list.children.length) { closeSugg = popover(list, wrap); input.focus(); } else closeSugg = () => {};
  };
  input.addEventListener("input", suggest);
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === "," || e.key === " ") { e.preventDefault(); if (input.value.trim()) { addTag(input.value); closePopover(); renderHeader(); } }
    else if (e.key === "Backspace" && !input.value && cur().tags.length) { cur().tags.pop(); touch(); view.rail(); closePopover(); renderHeader(); }
    else if (e.key === "Escape") { closePopover(); renderHeader(); }
  });
  input.addEventListener("blur", () => setTimeout(() => { if (document.activeElement !== input && input.isConnected) { if (input.value.trim()) addTag(input.value); closePopover(); renderHeader(); } }, 120));
  suggest();
}

export function renderHeader(): void {
  const host = document.querySelector(".header") as HTMLElement | null;
  const pad = state.current;
  if (!host || !pad) return;
  const dateBtn = el("button", { class: "date", "aria-label": `Change date: ${longDate(pad.date)}`, onClick: () => openDatePicker(dateBtn, "move") },
    el("span", { class: "lbl" }, "DATE"), el("span", { class: "val" }, longDate(pad.date)), el("span", { class: "cal", html: I.calendar }));
  const title = el("input", { value: pad.title, placeholder: "Untitled sheet", "aria-label": "Sheet title",
    onInput: (e: Event) => { pad.title = (e.target as HTMLInputElement).value; touch(); const row = document.querySelector(`.rail [data-sheet-id="${pad.id}"] .name`); if (row) row.textContent = pad.title.trim() || "Untitled sheet"; } });
  const addBtn = el("button", { class: "chip add", onClick: () => openTagInput(addBtn) }, "+ tag");
  host.replaceChildren(dateBtn, el("label", { class: "title" }, title), el("div", { class: "tags" }, ...pad.tags.map(chip), addBtn));
}

export const todayLabel = () => dayKey();
