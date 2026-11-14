defmodule RegentsWeb.Components.LabBlocks.Scene do
  @moduledoc """
  The Overview hero's scene: each product a block floating at its own depth in a
  deep square tunnel, the crown's thirteen blocks set into the far wall, and a
  thin beam for each way two products work together.

  Each product's block is placed by where it lands on the stage and how far
  away it is; the scene works out where that is in space, so the composition is
  drawn as it is seen and the depth comes from the distances. It is composed
  twice, for a wide stage and a narrow one, each of fixed proportions.
  """

  alias RegentsWeb.Components.LabBlocks.{Camera, Still}

  @eye {0.0, 0.0, 16.0}
  @fov 30.0
  # Turned so a top and two sides show: the same for every block, as one light falls on them all.
  @yaw 35
  @pitch 24
  @light Camera.normalize({-0.55, 0.72, 0.42})

  # Where each block lands, in % across and down, how far away it is, and where its name sits.
  @wide %{
    "Cloak" => {{22, 23}, 21.0, "above-end"},
    "Autolaunch" => {{56, 8}, 19.0, "left"},
    "Keyfleet" => {{80, 14}, 12.8, "above-start"},
    "Patchbay" => {{9, 59}, 16.0, "below"},
    "Protocol" => {{68, 60}, 13.6, "below-end"},
    "Techtree" => {{39, 85}, 14.6, "below-end"},
    "Sign-in with Agent" => {{92, 86}, 16.6, "below-end"}
  }

  # On a narrow stage the blocks ring the crown, so every line crosses open space
  # wide enough to press, and Sign-in with Agent keeps the bottom right corner.
  @narrow %{
    "Cloak" => {{9, 86}, 21.0, "above-start"},
    "Autolaunch" => {{41, 79}, 19.0, "below"},
    "Keyfleet" => {{12, 13}, 12.8, "above-start"},
    "Patchbay" => {{92, 39}, 16.0, "left"},
    "Protocol" => {{58, 13}, 13.6, "above"},
    "Techtree" => {{18, 60}, 14.6, "below"},
    "Sign-in with Agent" => {{92, 87}, 16.6, "below-end"}
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
        {spot, depth, side} = Map.fetch!(at, place.name)

        %{
          node: place.name,
          base: place.base,
          side: side,
          center: Camera.unproject(camera, spot, depth),
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

  # The crown's blocks, coloured along the house gradient from its top left to
  # its foot right, as the GPU picture colours them by `t`. They face the camera,
  # and each front face shows the crown's own colours under the light.
  defp crown(far, size) do
    {hx, hy, hz} = @crown_half
    half = {hx * size, hy * size, hz * size}
    exposure = 1 / Still.lighting({0.0, 0.0, 1.0}, @light)

    Enum.map(@crown_cells, fn {x, y} ->
      t = ((x + 2) / 4 + (1 - y) / 2) / 2
      percent = Float.round(t * 100, 1)

      %{
        node: nil,
        center: {x * size, y * size, far + hz * size},
        half: half,
        axes: [{1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}],
        exposure: exposure,
        t: t,
        base:
          "color-mix(in srgb, var(--lab-blocks-crown-foot) #{percent}%, var(--lab-blocks-crown-top))"
      }
    end)
  end

  @doc """
  The tunnel as still shapes, with the gradients its seams are drawn in: each
  band of each wall in its step from the near colour to the far one, the far
  wall, and on each wall the seams between the tiles, which come in along the
  wall so nothing marks the rim. The GPU picture (`tunnel` in
  `assets/js/lab_blocks/shaders.ts`) draws the same.
  """
  def tunnel(scene, id) do
    %{width: w, height: h, far: far} = tunnel = scene.tunnel
    camera = scene.camera
    count = round((tunnel.near - far) / tunnel.step)
    polygon = &(Still.path(camera, &1) <> "Z")

    bands =
      for k <- 0..(count - 1), {wall, slope} <- @walls do
        side = across(tunnel, wall)
        corners = [{-side, k}, {side, k}, {side, k + 1}, {-side, k + 1}]

        %{
          d: polygon.(Enum.map(corners, fn {along, u} -> on(tunnel, wall, along, u) end)),
          fill: ramp(min(1.0, k / count * slope))
        }
      end

    far_wall = %{
      d: polygon.([{-w, -h, far}, {w, -h, far}, {w, h, far}, {-w, h, far}]),
      fill: "var(--lab-blocks-far)"
    }

    seams =
      for {wall, _slope} <- @walls, do: wall_seams(tunnel, camera, count, wall, "#{id}-#{wall}")

    %{
      shapes: bands ++ [far_wall] ++ Enum.map(seams, & &1.shape),
      gradients: Enum.map(seams, & &1.gradient)
    }
  end

  # One wall's seams between its tiles, run its whole depth, and the gradient they
  # are drawn in, which brings them in along the wall from the rim.
  defp wall_seams(tunnel, camera, count, wall, id) do
    half = across(tunnel, wall)
    tiles = for i <- -10..10, abs(i * tunnel.tile) < half - 0.01, do: i * tunnel.tile
    at = &Still.at(camera, on(tunnel, wall, 0.0, &1))
    {from, to} = {at.(@seam_from), at.(@seam_to)}

    stops =
      for i <- 0..6 do
        u = @seam_from + (@seam_to - @seam_from) * i / 6
        {offset(at.(u), from, to), seam_colour(seam(u))}
      end

    segments = Enum.map(tiles, &[on(tunnel, wall, &1, 0), on(tunnel, wall, &1, count)])

    %{
      shape: %{
        d: Enum.map_join(segments, " ", &Still.path(camera, &1)),
        class: "lab-blocks__seam",
        stroke: "url(##{id})"
      },
      gradient: %{id: id, from: from, to: to, stops: stops}
    }
  end

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

  defp seam_colour(share) when share >= 0.999, do: "var(--lab-blocks-seam)"

  defp seam_colour(share),
    do: "color-mix(in srgb, var(--lab-blocks-seam) #{Float.round(share * 100, 1)}%, transparent)"

  # A band's colour: it takes the far colour slowly near the rim and faster deeper in.
  defp ramp(share) do
    "color-mix(in srgb, var(--lab-blocks-far) #{Float.round(share * :math.sqrt(share) * 100, 1)}%, var(--lab-blocks-near))"
  end

  @doc "What the GPU picture needs, as plain lists: everything but the colours, which the theme gives."
  def to_json(scene) do
    [block | _] = scene.blocks
    [crown | _] = scene.crown
    list = &Tuple.to_list/1

    %{
      camera: Camera.to_json(scene.camera),
      light: list.(scene.light),
      half: elem(block.half, 0),
      axes: Enum.map(block.axes, list),
      blocks: Enum.map(scene.blocks, &list.(&1.center)),
      crown: %{
        half: list.(crown.half),
        exposure: crown.exposure,
        cells: Enum.map(scene.crown, &(list.(&1.center) ++ [&1.t]))
      },
      lines: Enum.map(scene.lines, &list.(&1)),
      tunnel: %{
        half: [scene.tunnel.width, scene.tunnel.height],
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
