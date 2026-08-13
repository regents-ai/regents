export type ShellState = {
  routeId: string
  destination: string
  menuOpen: boolean
  presentation: string
  supportsPresentation: boolean
}

export type ShellBrand = "platform" | "autolaunch" | "techtree"

export function brandForShellApp(app: string | undefined): ShellBrand {
  if (app === "autolaunch" || app === "techtree") return app
  return "platform"
}

export function reconcileShellState(
  current: ShellState,
  incoming: Pick<
    ShellState,
    | "routeId"
    | "destination"
    | "presentation"
    | "supportsPresentation"
  >,
): ShellState {
  const destinationChanged = current.destination !== incoming.destination
  const preservePresentation = current.supportsPresentation && incoming.supportsPresentation

  return {
    routeId: incoming.routeId,
    destination: incoming.destination,
    menuOpen: destinationChanged ? false : current.menuOpen,
    presentation: preservePresentation ? current.presentation : incoming.presentation,
    supportsPresentation: incoming.supportsPresentation,
  }
}

export function shellDestinationChanged(
  current: Pick<ShellState, "destination">,
  incoming: Pick<ShellState, "destination">,
): boolean {
  return current.destination !== incoming.destination
}
