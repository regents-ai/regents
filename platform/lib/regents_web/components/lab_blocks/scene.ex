defmodule RegentsWeb.Components.LabBlocks.Scene do
  @moduledoc """
  The Overview hero's scene: each product a block floating at its own depth in a
  deep square tunnel, the crown's thirteen blocks set into the far wall, and a
  thin beam for each way two products work together.

  Each product's block is placed by where it lands on the stage and how far
  away it is; the scene works out where that is in space, so the composition is
  drawn as it is seen and the depth comes from the distances. It is composed
  twice, for a wide stage and a narrow one, each of fixed proportions; a block
  is as far away on both, so it is lit, fogged and joined alike on both.
  """

  alias RegentsWeb.Components.LabBlocks.{Camera, Still}

  @eye {0.0, 0.0, 16.0}
  @fov 30.0
  # Turned so a top and two sides show: the same for every block, as one light falls on them all.
  @yaw 35
  @pitch 24
  @light Camera.normalize({-0.55, 0.72, 0.42})

  # How far away each block is, on every stage.
  @depth %{
    "Cloak" => 21.0,
    "Autolaunch" => 19.0,
    "Keyfleet" => 12.8,
    "Patchbay" => 16.0,
    "Protocol" => 13.6,
    "Techtree" => 14.6,
    "Sign-in with Agent" => 16.6
  }

  # Where each block lands, in % across and down, and where its name sits.
  @wide %{
    "Cloak" => {{22, 23}, "above-end"},
    "Autolaunch" => {{56, 8}, "left"},
    "Keyfleet" => {{80, 14}, "above-start"},
    "Patchbay" => {{9, 59}, "below"},
    "Protocol" => {{68, 60}, "below-end"},
    "Techtree" => {{39, 85}, "below-end"},
    "Sign-in with Agent" => {{92, 86}, "below-end"}
  }

  # On a narrow stage the blocks ring the crown, so every line crosses open space
  # wide enough to press, and Sign-in with Agent keeps the bottom right corner.
  @narrow %{
    "Cloak" => {{9, 86}, "above-start"},
    "Autolaunch" => {{41, 79}, "below"},
    "Keyfleet" => {{12, 13}, "above-start"},
    "Patchbay" => {{92, 39}, "left"},
    "Protocol" => {{58, 13}, "above"},
    "Techtree" => {{18, 60}, "below"},
    "Sign-in with Agent" => {{92, 87}, "below-end"}
  }

  # Each composition: the stage's proportions, where its blocks land, half a
  # block's size, and how large the crown is.
  @layouts %{
    wide: %{aspect: 1.2, at: @wide, half: 0.36, crown: 1.0},
    narrow: %{aspect: 0.62, at: @narrow, half: 0.26, crown: 0.72}
  }

  # The tunnel: half its height (its width follows the stage, so its rim is the
  # stage's edge), where it starts and ends along the view, how deep each band
  # is and how wide a tile.
  @tunnel %{height: 3.3, near: 4.0, far: -26.0, step: 2.0, tile: 1.1}

  # How quickly each wall's bands take the far colour, against the floor's. Every
  # wall starts in the near colour and takes the far one slowly at first, so the
  # tunnel's rim is the panel it sits in.
  @walls [floor: 1.0, left: 1.15, right: 1.15, ceiling: 1.3]

  # Each wall's part of the stage, a triangle from the stage's edge to its
  # middle, about the middle.
  @ring [
    floor: "M-50 50H50L0 0Z",
    left: "M-50-50V50L0 0Z",
    right: "M50-50V50L0 0Z",
    ceiling: "M-50-50H50L0 0Z"
  ]

  # Where along the walls, in bands from the rim, the seams start to show and
  # where they show in full.
  @seam_from 0.5
  @seam_to 5.0

  # The crown on a five-column grid, one unit apart, y up; each block nearly a
  # unit square and a little proud of the far wall.
  @crown_cells [{-2, 1}, {0, 1}, {2, 1}] ++ for(x <- -2..2, y <- [0, -1], do: {x, y})
  @crown_half {0.47, 0.47, 0.2}

  @doc """
  The scene for one layout: its camera and light, a block for each place (in
  their order), the crown's blocks, a beam for each link between its two places'
  blocks, and the tunnel.
  """
  def compose(layout, places, links) do
    %{aspect: aspect, at: at, half: half, crown: size} = Map.fetch!(@layouts, layout)
    camera = Camera.new(@eye, {0.0, 0.0, 0.0}, @fov, aspect)
    axes = axes()
    tunnel = Map.put(@tunnel, :width, @tunnel.height * aspect)

    blocks =
      Enum.map(places, fn place ->
        {spot, side} = Map.fetch!(at, place.name)

        %{
          node: place.name,
          base: place.base,
          side: side,
          center: Camera.unproject(camera, spot, Map.fetch!(@depth, place.name)),
          half: {half, half, half},
          axes: axes,
          exposure: 1.0
        }
      end)

    index = Map.new(Enum.with_index(blocks), fn {block, index} -> {block.node, index} end)

    %{
      aspect: aspect,
      camera: camera,
      light: @light,
      blocks: blocks,
      crown: crown(tunnel.far, size),
      lines: Enum.map(links, &{index[&1.from], index[&1.to]}),
      tunnel: tunnel
    }
  end

  # The crown's blocks, each with its place `t` along the house gradient from
  # the crown's top left to its foot right, which both pictures colour it by.
  # They face the camera, and each front face shows the crown's own colours
  # under the light.
  defp crown(far, size) do
    {hx, hy, hz} = @crown_half
    half = {hx * size, hy * size, hz * size}
    exposure = 1 / Still.lighting({0.0, 0.0, 1.0}, @light)

    Enum.map(@crown_cells, fn {x, y} ->
      %{
        node: nil,
        center: {x * size, y * size, far + hz * size},
        half: half,
        axes: [{1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}],
        exposure: exposure,
        t: ((x + 2) / 4 + (1 - y) / 2) / 2
      }
    end)
  end

  @doc """
  How the narrow stage's crown is the wide one's scaled about the stage's
  middle, `{across, down}`. The crown shows only its blocks' fronts, which face
  the view and lie at one depth, so a scale carries one crown onto the other.
  """
  def crown_scale(wide, narrow) do
    [{wx, wy}, {nx, ny}] =
      for %{camera: camera, crown: [cell | _]} <- [wide, narrow] do
        {x, y, z} = cell.center
        {hx, hy, hz} = cell.half
        {px, py, _depth} = Camera.project(camera, {x + hx, y + hy, z + hz})
        {px - 50, py - 50}
      end

    {Float.round(nx / wx, 4), Float.round(ny / wy, 4)}
  end

  @doc """
  The tunnel as the still picture draws it. Its width follows the stage, so
  all of this is the same on every stage. Each ring of the tunnel from the rim
  in is the `:ring`: each wall a triangle from the stage's edge to its middle,
  with the share of the far colour it gains a band (`:step`). The ring is drawn
  once for each band, the `k`th of `:rings` scaled round the middle by the
  `k`th scale, and there each wall takes `min(1, k * step) ^ 1.5` of the far
  colour, slowly near the rim and faster deeper in; drawn from the rim in, each
  ring covers all but the band of the one before. Then the far wall (a path,
  `:far`), and how the seams come in along each wall, so nothing marks the rim
  (`:fades`, each wall's line from where its seams start to show to where they
  show in full, and `:fade`, how strongly they show along it). The GPU picture
  (`tunnel` in `assets/js/lab_blocks/shaders.ts`) draws the same.
  """
  def tunnel(scene) do
    %{camera: camera, tunnel: tunnel} = scene
    count = bands(tunnel)
    # How far a ring `u` bands in reaches from the middle, in %.
    reach = &(elem(Camera.project(camera, on(tunnel, :floor, 0.0, &1)), 1) - 50)
    at = &Still.at(camera, on(tunnel, &1, 0.0, &2))
    {from, to} = {at.(:floor, @seam_from), at.(:floor, @seam_to)}
    {low, high} = {Still.num(50 - reach.(count)), Still.num(50 + reach.(count))}

    %{
      ring: for({wall, d} <- @ring, do: %{d: d, step: Float.round(@walls[wall] / count, 5)}),
      rings: for(k <- 0..(count - 1), do: Float.round(reach.(k) / 50, 4)),
      far: "M#{low} #{low}H#{high}V#{high}H#{low}Z",
      fades:
        for {wall, _slope} <- @walls do
          %{wall: wall, from: at.(wall, @seam_from), to: at.(wall, @seam_to)}
        end,
      fade:
        for i <- 0..6 do
          u = @seam_from + (@seam_to - @seam_from) * i / 6
          {offset(at.(:floor, u), from, to), Float.round(seam(u), 3)}
        end
    }
  end

  @doc """
  The given walls' seams between their tiles on this stage, run the tunnel's
  whole depth, as `{wall, path}`. A tile is as wide on every stage, so how many
  cross the floor and the ceiling follows the stage's width, while the side
  walls' are the same on every stage.
  """
  def seams(scene, walls) do
    %{camera: camera, tunnel: tunnel} = scene

    for wall <- walls do
      half = across(tunnel, wall)
      tiles = for i <- -10..10, abs(i * tunnel.tile) < half - 0.01, do: i * tunnel.tile

      {wall,
       Enum.map_join(tiles, fn along ->
         Still.path(camera, [on(tunnel, wall, along, 0), on(tunnel, wall, along, bands(tunnel))])
       end)}
    end
  end

  defp bands(tunnel), do: round((tunnel.near - tunnel.far) / tunnel.step)

  # How far a wall reaches to each side of its middle.
  defp across(tunnel, wall) when wall in [:floor, :ceiling], do: tunnel.width
  defp across(tunnel, _wall), do: tunnel.height

  # A point on a wall: `along` its width or height, `u` bands in from the rim.
  defp on(tunnel, wall, along, u) do
    z = tunnel.near - u * tunnel.step

    case wall do
      :floor -> {along, -tunnel.height, z}
      :ceiling -> {along, tunnel.height, z}
      :left -> {-tunnel.width, along, z}
      :right -> {tunnel.width, along, z}
    end
  end

  @doc "How strongly the seams show `u` bands in from the rim: not at the rim, in full from the fifth band."
  def seam(u) do
    t = min(max((u - @seam_from) / (@seam_to - @seam_from), 0.0), 1.0)
    t * t * (3 - 2 * t)
  end

  # How far a point lies along a gradient from `from` to `to`.
  defp offset({x, y}, {x0, y0}, {x1, y1}) do
    {dx, dy} = {x1 - x0, y1 - y0}
    Float.round(((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy), 3)
  end

  @doc """
  What the GPU picture needs, as plain lists: everything but the colours, which
  the theme gives. Places in space are rounded to a ten-thousandth, far finer
  than a pixel.
  """
  def to_json(scene) do
    [block | _] = scene.blocks
    [crown | _] = scene.crown
    list = &Enum.map(Tuple.to_list(&1), fn value -> Float.round(value * 1.0, 4) end)

    %{
      camera: Camera.to_json(scene.camera),
      light: list.(scene.light),
      half: elem(block.half, 0),
      axes: Enum.map(block.axes, list),
      blocks: Enum.map(scene.blocks, &list.(&1.center)),
      crown: %{
        half: list.(crown.half),
        exposure: Float.round(crown.exposure, 4),
        cells: Enum.map(scene.crown, &(list.(&1.center) ++ [&1.t]))
      },
      lines: Enum.map(scene.lines, &Tuple.to_list/1),
      tunnel: %{
        half: list.({scene.tunnel.width, scene.tunnel.height}),
        near: scene.tunnel.near,
        far: scene.tunnel.far,
        step: scene.tunnel.step,
        tile: scene.tunnel.tile
      }
    }
  end

  defp axes do
    {sy, cy} = sin_cos(@yaw)
    {sp, cp} = sin_cos(@pitch)

    [
      {cy, sy * sp, -sy * cp},
      {0.0, cp, sp},
      {sy, -cy * sp, cy * cp}
    ]
  end

  defp sin_cos(degrees) do
    radians = degrees * :math.pi() / 180
    {:math.sin(radians), :math.cos(radians)}
  end
end
