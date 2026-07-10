export type ThemeChoice = "system" | "light" | "dark"

export const themeStorageKey = "regent:theme"

export function isThemeChoice(value: string | null): value is ThemeChoice {
  return value === "system" || value === "light" || value === "dark"
}

export function resolveTheme(choice: ThemeChoice, prefersDark: boolean): "light" | "dark" {
  return choice === "system" ? (prefersDark ? "dark" : "light") : choice
}

export function readTheme(storage: Pick<Storage, "getItem">): ThemeChoice {
  const stored = storage.getItem(themeStorageKey)
  return isThemeChoice(stored) ? stored : "system"
}

export function applyTheme(
  root: Pick<HTMLElement, "dataset">,
  storage: Pick<Storage, "setItem">,
  choice: ThemeChoice,
  prefersDark: boolean,
): void {
  storage.setItem(themeStorageKey, choice)
  root.dataset.theme = resolveTheme(choice, prefersDark)
  root.dataset.themeChoice = choice
}
