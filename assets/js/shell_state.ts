export type ShellState = {
  routeId: string
  destination: string
  menuOpen: boolean
}

export type ShellBrand = "platform" | "autolaunch"

export function brandForShellApp(app: string | undefined): ShellBrand {
  if (app === "autolaunch") return app
  return "platform"
}

export function reconcileShellState(
  current: ShellState,
  incoming: Pick<ShellState, "routeId" | "destination">,
): ShellState {
  const destinationChanged = current.destination !== incoming.destination

  return {
    routeId: incoming.routeId,
    destination: incoming.destination,
    menuOpen: destinationChanged ? false : current.menuOpen,
  }
}

export function shellDestinationChanged(
  current: Pick<ShellState, "destination">,
  incoming: Pick<ShellState, "destination">,
): boolean {
  return current.destination !== incoming.destination
}
