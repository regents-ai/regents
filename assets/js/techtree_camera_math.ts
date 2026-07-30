export const CAMERA_ZOOM_MIN = 0.3
export const CAMERA_ZOOM_MAX = 2

export type CameraTransform = {
  x: number
  y: number
  zoom: number
}

export type CameraPoint = {
  x: number
  y: number
}

export type CameraRect = CameraPoint & {
  width: number
  height: number
}

export type CameraEdge = {
  kind: string
  fromNodeId: string
  toNodeId: string
}

export type CameraNode = CameraRect & {
  id: string
}

export const clampZoom = (
  zoom: number,
  minimum = CAMERA_ZOOM_MIN,
  maximum = CAMERA_ZOOM_MAX,
) => Math.min(Math.max(zoom, minimum), maximum)

export const fitCamera = (
  viewport: Pick<CameraRect, "width" | "height">,
  bounds: CameraRect,
  margin: number,
  maximumZoom = CAMERA_ZOOM_MAX,
): CameraTransform => {
  const availableWidth = Math.max(viewport.width - margin * 2, 1)
  const availableHeight = Math.max(viewport.height - margin * 2, 1)
  const zoom = clampZoom(
    Math.min(
      availableWidth / Math.max(bounds.width, 1),
      availableHeight / Math.max(bounds.height, 1),
    ),
    CAMERA_ZOOM_MIN,
    maximumZoom,
  )

  return {
    x: viewport.width / 2 - (bounds.x + bounds.width / 2) * zoom,
    y: viewport.height / 2 - (bounds.y + bounds.height / 2) * zoom,
    zoom,
  }
}

export const zoomCameraAt = (
  camera: CameraTransform,
  point: CameraPoint,
  requestedZoom: number,
): CameraTransform => {
  const zoom = clampZoom(requestedZoom)
  const worldX = (point.x - camera.x) / camera.zoom
  const worldY = (point.y - camera.y) / camera.zoom

  return {
    x: point.x - worldX * zoom,
    y: point.y - worldY * zoom,
    zoom,
  }
}

export const focusNodeIds = (selectedNodeId: string, edges: CameraEdge[]) => {
  const ids = new Set([selectedNodeId])

  edges.forEach((edge) => {
    if (edge.kind !== "prerequisite") return
    if (edge.fromNodeId === selectedNodeId) ids.add(edge.toNodeId)
    if (edge.toNodeId === selectedNodeId) ids.add(edge.fromNodeId)
  })

  return ids
}

export const boundsForNodes = (
  nodes: CameraNode[],
  nodeIds: ReadonlySet<string>,
): CameraRect | null => {
  const focused = nodes.filter((node) => nodeIds.has(node.id))
  if (focused.length === 0) return null

  const left = Math.min(...focused.map((node) => node.x))
  const top = Math.min(...focused.map((node) => node.y))
  const right = Math.max(...focused.map((node) => node.x + node.width))
  const bottom = Math.max(...focused.map((node) => node.y + node.height))

  return {x: left, y: top, width: right - left, height: bottom - top}
}
