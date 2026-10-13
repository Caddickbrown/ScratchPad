// The to-do column: live count, one blank row, sort, grip drag, tick / stamp / hop motion.
import { api } from "./api";
import { pointInVisible, textBlockAt } from "./canvas";
import { todosMarkdown } from "./markdown";
import { after, burst, moving, replay } from "./motion";
import { counts, filled, isOverdue, moveTodo, newTodo, nextStatus, sortTodos, todayKey, type SortMode, type Todo } from "./model";
import { once, prefs, setPref } from "./prefs";
import { cur, state, touch, upsert, view } from "./state";
import { $, el, I, menu, toast } from "./ui";

const SORTS: { value: SortMode; label: string }[] = [
  { value: "manual", label: "Manual (drag)" }, { value: "open", label: "Open first" }, { value: "overdue", label: "Overdue first" },
  { value: "az", label: "A to Z" }, { value: "oldest", label: "Oldest first" },
];

const statusLabel = (t: Todo) => `Status: ${t.status}. Click to change`;

export function renderTodos(): void {
  const aside = $(".todo");
  const pad = state.current;
  if (!aside || !pad) return;
  const list = el("ol", { class: "rows" });
  const shown = sortTodos(pad.todos.filter(filled), prefs.todoSort, prefs.sink);
  const hop = state.hopSheet === pad.id;
  shown.forEach((t, i) => {
    const li = row(t);
    if (hop && t.carriedFrom && moving()) { li.classList.add("hop"); li.style.animationDelay = `${i * 90}ms`; }
    list.append(li);
  });
  state.hopSheet = null;
  list.append(blankRow());
  const sortLabel = SORTS.find((s) => s.value === prefs.todoSort)!.label.replace(" (drag)", "");
  const sortBtn = el("button", { class: "tool sort", "aria-label": `Sort: ${sortLabel}`, onClick: () => openSortMenu(sortBtn) },
    el("span", { html: I.sort }), el("span", {}, sortLabel), el("span", { html: I.chevron }));
  aside.replaceChildren(
    el("div", { class: "todo-head" }, el("span", { class: "ttl" }, "To-do"), el("span", { class: "count", "aria-live": "polite" })),
    el("div", { class: "todo-tools" }, sortBtn, el("span", { class: "spacer" }),
      el("button", { class: "tool icon", "aria-label": "Copy to-dos as Markdown", title: "Copy as Markdown", html: I.markdown, onClick: copyMarkdown }),
      el("button", { class: "tool icon", "aria-label": "Clear done", title: "Clear done", html: I.clearDone, onClick: clearDone })),
    list,
    el("div", { class: "stamp-slot" }),
    el("div", { class: "todo-foot" },
      el("button", { class: "add", onClick: () => focusBlank() }, el("span", { html: I.plus }), "Add to-do"),
      el("span", { class: "carry" })),
  );
  refreshMeta(false);
}

function row(t: Todo): HTMLLIElement {
  const li = el("li", { "data-id": t.id }) as HTMLLIElement;
  const grip = el("button", { class: "grip", "aria-label": "Drag to reorder, or onto the sheet", title: "Drag to reorder, onto the sheet, or onto another sheet", html: I.grip });
  const circle = el("button", { class: "circle", "aria-label": statusLabel(t) }, el("span", { class: "dot" }));
  const input = el("input", { value: t.text, "aria-label": "To-do", placeholder: "" }) as HTMLInputElement;
  li.append(grip, circle, el("div", { class: "txt" }, input, el("span", { class: "strike", "aria-hidden": "true" })));
  paint(li, t);
  circle.addEventListener("click", () => cycle(t, li));
  input.addEventListener("input", () => { t.text = input.value; touch(); refreshMeta(); });
  input.addEventListener("keydown", (e) => keys(e, t, li, input));
  wireGrip(grip, li, t);
  return li;
}

function paint(li: HTMLElement, t: Todo): void {
  li.className = [t.status, isOverdue(t) ? "overdue" : "", li.classList.contains("hop") ? "hop" : ""].filter(Boolean).join(" ");
  const dot = li.querySelector(".dot")!;
  dot.innerHTML = t.status === "done" ? I.check : t.status === "deferred" ? I.slash : "";
  const strike = li.querySelector(".strike") as HTMLElement;
  strike.style.width = `${Math.min(Math.round(measure(t.text, li)), 240)}px`;
  li.querySelector(".circle")!.setAttribute("aria-label", statusLabel(t));
}

let measurer: CanvasRenderingContext2D | null = null;
function measure(text: string, li: HTMLElement): number {
  measurer ??= document.createElement("canvas").getContext("2d");
  const input = li.querySelector("input");
  if (!measurer || !input) return text.length * 6.6;
  measurer.font = getComputedStyle(input).font || "13px sans-serif";
  return measurer.measureText(text).width;
}

function blankRow(): HTMLLIElement {
  const li = el("li", { class: "blank" }) as HTMLLIElement;
  const input = el("input", { "aria-label": "New to-do", placeholder: "New to-do" }) as HTMLInputElement;
  li.append(el("span", { class: "grip ghost", "aria-hidden": "true" }), el("span", { class: "circle ghost", "aria-hidden": "true" }, el("span", { class: "dot" })), el("div", { class: "txt" }, input));
  input.addEventListener("input", () => {
    if (!input.value) return;
    const t = newTodo(input.value);
    cur().todos.push(t);
    touch();
    const real = row(t);
    li.replaceWith(real);
    const ri = real.querySelector("input") as HTMLInputElement;
    ri.focus();
    ri.setSelectionRange(ri.value.length, ri.value.length);
    $(".todo .rows")?.append(blankRow());
    refreshMeta();
  });
  input.addEventListener("keydown", (e) => {
    if (e.key === "ArrowUp") { e.preventDefault(); (li.previousElementSibling?.querySelector("input") as HTMLInputElement | null)?.focus(); }
  });
  return li;
}

export function focusBlank(): void {
  const input = $(".todo li.blank input") as HTMLInputElement | null;
  if (!input) return;
  input.focus();
  if (moving()) replay(input.closest("li")!, "fresh");
}

function keys(e: KeyboardEvent, t: Todo, li: HTMLElement, input: HTMLInputElement): void {
  const pad = cur();
  const sib = (d: -1 | 1) => (d < 0 ? li.previousElementSibling : li.nextElementSibling)?.querySelector("input") as HTMLInputElement | null;
  if (e.key === "Enter") {
    e.preventDefault();
    const n = newTodo();
    pad.todos.splice(pad.todos.indexOf(t) + 1, 0, n);
    const nli = row(n);
    li.after(nli);
    if (moving()) nli.classList.add("fresh");
    (nli.querySelector("input") as HTMLInputElement).focus();
    touch();
  } else if (e.key === "Backspace" && input.value === "") {
    e.preventDefault();
    const prev = sib(-1) ?? sib(1);
    pad.todos = pad.todos.filter((x) => x.id !== t.id);
    li.remove();
    prev?.focus();
    touch();
    refreshMeta();
  } else if (e.altKey && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
    e.preventDefault();
    const other = (e.key === "ArrowUp" ? li.previousElementSibling : li.nextElementSibling) as HTMLElement | null;
    if (!other || other.classList.contains("blank")) return;
    adoptViewOrder();
    pad.todos = moveTodo(pad.todos, t.id, e.key === "ArrowUp" ? other.dataset.id! : (other.nextElementSibling as HTMLElement | null)?.dataset.id ?? null);
    touch();
    renderTodos();
    (document.querySelector(`.todo li[data-id="${t.id}"] input`) as HTMLInputElement | null)?.focus();
  } else if (e.key === "ArrowUp") { e.preventDefault(); sib(-1)?.focus(); }
  else if (e.key === "ArrowDown") { e.preventDefault(); sib(1)?.focus(); }
  else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "d") { e.preventDefault(); cycle(t, li); }
}

function cycle(t: Todo, li: HTMLElement): void {
  if (!filled(t)) return;
  t.status = nextStatus[t.status];
  touch();
  paint(li, t);
  if (t.status === "done" && moving()) {
    replay(li, "ticking");
    burst(li.querySelector(".circle") as HTMLElement);
    after(800, () => li.classList.remove("ticking"));
  }
  refreshMeta();
  if (prefs.sink || prefs.todoSort !== "manual") after(700, () => { if (state.current === cur()) renderTodos(); });
}

/** Count, footer, and the all-clear stamp. */
function refreshMeta(animate = true): void {
  const pad = state.current;
  const aside = $(".todo");
  if (!pad || !aside) return;
  const c = counts(pad);
  const count = aside.querySelector(".count") as HTMLElement;
  const text = `${c.done} of ${c.total} done`;
  if (count.textContent !== text) { count.textContent = text; if (animate && moving()) replay(count, "bump"); }
  aside.querySelector(".carry")!.textContent = c.open ? `${c.open} open will carry to tomorrow` : c.total ? "Nothing to carry. Nice." : "Nothing here yet";
  const slot = aside.querySelector(".stamp-slot") as HTMLElement;
  const clear = c.total > 0 && c.open === 0 && c.done > 0;
  if (!clear) { slot.replaceChildren(); return; }
  if (slot.firstChild) return;
  const stamp = el("div", { class: "stamp", role: "status" }, "All clear");
  slot.append(stamp);
  if (animate && once(`stamp.${pad.id}.${todayKey()}`)) { stamp.classList.add("drop"); aside.classList.remove("thud"); void aside.offsetWidth; aside.classList.add("thud"); }
}

function openSortMenu(anchor: HTMLElement): void {
  menu([
    ...SORTS.map((s) => ({ label: s.label, checked: prefs.todoSort === s.value, run: () => { setPref("todoSort", s.value); renderTodos(); } })),
    "sep",
    { label: "Done sinks to the bottom", checked: prefs.sink, run: () => { setPref("sink", !prefs.sink); renderTodos(); } },
  ], anchor);
}

/** Writes the current view order into the file, then switches to Manual. */
function adoptViewOrder(): void {
  const pad = cur();
  if (prefs.todoSort === "manual" && !prefs.sink) return;
  const shown = sortTodos(pad.todos.filter(filled), prefs.todoSort, prefs.sink);
  pad.todos = [...shown, ...pad.todos.filter((t) => !filled(t))];
  if (prefs.todoSort !== "manual") setPref("todoSort", "manual");
}

async function copyMarkdown(): Promise<void> {
  const md = todosMarkdown([cur()], { includeDone: true, includeDeferred: true });
  try { await navigator.clipboard.writeText(md); toast("To-dos copied as Markdown"); } catch { toast("Could not reach the clipboard"); }
}

function clearDone(): void {
  const pad = cur();
  const before = pad.todos.slice();
  const removed = before.filter((t) => t.status === "done").length;
  if (!removed) { toast("Nothing done yet"); return; }
  const rows = [...document.querySelectorAll(".todo li.done")] as HTMLElement[];
  rows.forEach((r) => r.classList.add("leaving"));
  after(220, () => { pad.todos = pad.todos.filter((t) => t.status !== "done"); touch(); renderTodos(); });
  toast(`${removed} done cleared`, { label: "Undo", run: () => { if (state.current === pad) { pad.todos = before; touch(); renderTodos(); } } });
}

// ---------- drag ----------

function wireGrip(grip: HTMLElement, li: HTMLElement, t: Todo): void {
  grip.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    const sx = e.clientX, sy = e.clientY;
    let ghost: HTMLElement | null = null;
    let target: { kind: "row"; id: string | null; el: HTMLElement } | { kind: "canvas" } | { kind: "sheet"; id: string; el: HTMLElement } | null = null;
    const clear = () => {
      document.querySelectorAll(".drop-before, .drop-after, .drop-target").forEach((x) => x.classList.remove("drop-before", "drop-after", "drop-target"));
    };
    const onMove = (ev: PointerEvent) => {
      if (!ghost && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 5) return;
      if (!ghost) {
        ghost = el("div", { class: "todo-ghost", "aria-hidden": "true" }, t.text || "(empty)");
        document.body.append(ghost);
        li.classList.add("lifting");
      }
      ghost.style.left = `${ev.clientX + 12}px`;
      ghost.style.top = `${ev.clientY - 16}px`;
      clear();
      target = null;
      const under = document.elementFromPoint(ev.clientX, ev.clientY) as HTMLElement | null;
      const overRow = under?.closest(".todo li") as HTMLElement | null;
      const overSheet = under?.closest(".rail [data-sheet-id]") as HTMLElement | null;
      if (overRow && overRow !== li) {
        const r = overRow.getBoundingClientRect();
        const before = ev.clientY < r.top + r.height / 2 || overRow.classList.contains("blank");
        overRow.classList.add(before ? "drop-before" : "drop-after");
        const id = before ? overRow.dataset.id ?? null : (overRow.nextElementSibling as HTMLElement | null)?.dataset.id ?? null;
        target = { kind: "row", id, el: overRow };
      } else if (overSheet && overSheet.dataset.sheetId !== cur().id) {
        overSheet.classList.add("drop-target");
        target = { kind: "sheet", id: overSheet.dataset.sheetId!, el: overSheet };
      } else if (pointInVisible(ev)) {
        $("#canvas")?.classList.add("drop-target");
        target = { kind: "canvas" };
      }
    };
    const onUp = async (ev: PointerEvent) => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      clear();
      ghost?.remove();
      li.classList.remove("lifting");
      if (!ghost || !target) return;
      const pad = cur();
      if (target.kind === "row") {
        adoptViewOrder();
        pad.todos = moveTodo(pad.todos, t.id, target.id);
        touch();
        renderTodos();
      } else if (target.kind === "canvas") {
        if (!filled(t)) return;
        pad.todos = pad.todos.filter((x) => x.id !== t.id);
        textBlockAt(t.text, pointInVisible(ev)!);
        renderTodos();
      } else {
        const dest = state.pads.find((p) => p.id === (target as any).id);
        if (!dest) return;
        const copy = structuredClone(dest);
        copy.todos.push({ ...t });
        copy.updatedAt = new Date().toISOString();
        try { await api.savePad(copy); } catch (e) { toast(`Could not move: ${e}`); return; }
        upsert(copy);
        pad.todos = pad.todos.filter((x) => x.id !== t.id);
        touch();
        renderTodos();
        view.rail();
        toast(`Moved to ${copy.title || "Untitled sheet"}`);
      }
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
  });
}
