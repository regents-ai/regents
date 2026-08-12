export type ShellState = {
  routeId: string
  destination: string
  menuOpen: boolean
  presentation: string
  supportsPresentation: boolean
  formationPanel: string
  supportsFormationPanel: boolean
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
    | "formationPanel"
    | "supportsFormationPanel"
  >,
): ShellState {
  const destinationChanged = current.destination !== incoming.destination
  const preservePresentation = current.supportsPresentation && incoming.supportsPresentation
  const preserveFormationPanel =
    current.supportsFormationPanel && incoming.supportsFormationPanel

  return {
    routeId: incoming.routeId,
    destination: incoming.destination,
    menuOpen: destinationChanged ? false : current.menuOpen,
    presentation: preservePresentation ? current.presentation : incoming.presentation,
    supportsPresentation: incoming.supportsPresentation,
    formationPanel: preserveFormationPanel ? current.formationPanel : incoming.formationPanel,
    supportsFormationPanel: incoming.supportsFormationPanel,
  }
}

export function shellDestinationChanged(
  current: Pick<ShellState, "destination">,
  incoming: Pick<ShellState, "destination">,
): boolean {
  return current.destination !== incoming.destination
}
