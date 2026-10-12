export type Appearance = "system" | "light" | "dark";
const KEY = "scratchpad.appearance";

export function loadAppearance(): Appearance {
  try {
    const v = localStorage.getItem(KEY);
    return v === "light" || v === "dark" ? v : "system";
  } catch {
    return "system";
  }
}

export function applyAppearance(a: Appearance): void {
  const root = document.documentElement;
  if (a === "system") root.removeAttribute("data-theme");
  else root.setAttribute("data-theme", a);
  try { localStorage.setItem(KEY, a); } catch { /* private window */ }
}

export const nextAppearance: Record<Appearance, Appearance> = { system: "light", light: "dark", dark: "system" };
