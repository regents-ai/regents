defmodule RegentsWeb.Components.LabBlocks.Still do
  @moduledoc """
  The Overview hero's still picture, as SVG shapes on a 100 by 100 stage.

  This is what a visitor sees before the GPU picture lands, without WebGPU, and
  when they asked for less motion, so it is the whole picture in its own right:
  every visible face of every block with its crisp gradient, the beams, and the
  tunnel behind them. The GPU picture (`assets/js/lab_blocks/shaders.ts`)
  shades each face and beam by the same rules, so the two meet when one fades
  over the other.

  A face is lit by how squarely it meets the scene's light, then shaded along
  itself: a side from its top edge down, a top from its back edge forward.
  A product far away takes a little of the tunnel's far colour, so depth reads in
  colour as well as in size; the crown is lit and keeps its own. Colours are CSS colours, so a block or beam whose
  colour follows the theme shades as well.
  """

  alias RegentsWeb.Components.LabBlocks.Camera

  # How bright a face is with no light on it, and how much the light adds.
  @ambient 0.46
  @diffuse 0.54
  # How much lighter the first edge of a face is than the second.
  @side_grade {1.08, 0.84}
  @top_grade {1.16, 0.98}
  @bottom_grade {0.6, 0.6}
  # The depths over which the far colour comes in, and the most of it anything takes.
  @fog_from 12.0
  @fog_to 44.0
  @fog_most 0.3
  # How much of its ends' own colour a beam keeps at rest; the rest is the theme's beam tone.
  @beam_share 0.62
  # A beam's width in CSS pixels at the camera's own distance from its target.
  @beam_width 1.4
  # A face turned this nearly edge on would draw only a sliver, so it is left out.
  @edge_on 0.1

  @doc "The share of the far colour a point this deep takes."
  def fog(depth), do: @fog_most * min(max((depth - @fog_from) / (@fog_to - @fog_from), 0.0), 1.0)

  @doc "How brightly the light falls on a face with this outward normal."
  def lighting(normal, light), do: @ambient + @diffuse * max(Camera.dot(normal, light), 0.0)

  @doc """
  Each block as the camera sees it, the farthest first: its `:node` and the
  shapes of the faces it shows, each with the gradient it fills with. A block is
  a map of `:center`, `:half` (half its size along each of its `:axes`), `:base`
  (its colour), `:exposure` (how much brighter than the light alone it is drawn)
  and `:node` (the place it is, or none for the crown's).
  """
  def solids(blocks, camera, light, id) do
    blocks
    |> Enum.with_index()
    |> Enum.sort_by(fn {block, _index} -> -distance(camera, block.center) end)
    |> Enum.map(fn {block, index} ->
      %{node: block.node, faces: faces(block, camera, light, "#{id}-b#{index}")}
    end)
  end

  defp faces(block, camera, light, prefix) do
    {hx, hy, hz} = block.half
    [ax, ay, az] = block.axes
    # The crown is lit and keeps its own colours; a product takes the far colour by its depth.
    base = if block.node, do: fogged(block.base, distance(camera, block.center)), else: block.base

    [
      {ax, hx, ay, hy, az, hz, :side, "x+"},
      {Camera.scale(ax, -1), hx, ay, hy, az, hz, :side, "x-"},
      {az, hz, ay, hy, ax, hx, :side, "z+"},
      {Camera.scale(az, -1), hz, ay, hy, ax, hx, :side, "z-"},
      {ay, hy, az, hz, ax, hx, :top, "y+"},
      {Camera.scale(ay, -1), hy, az, hz, ax, hx, :bottom, "y-"}
    ]
    |> Enum.flat_map(&face(block, base, camera, light, prefix, &1))
  end

  # One face, if the camera sees more of it than a sliver.
  defp face(block, base, camera, light, prefix, {normal, h, up, hu, across, ha, kind, key}) do
    middle = Camera.add(block.center, Camera.scale(normal, h))

    if Camera.facing(camera, normal, middle) > @edge_on do
      corners =
        for {u, a} <- [{1, 1}, {1, -1}, {-1, -1}, {-1, 1}] do
          middle
          |> Camera.add(Camera.scale(up, u * hu))
          |> Camera.add(Camera.scale(across, a * ha))
        end

      # A side runs from its top edge down; a top from its back edge forward.
      {first, second} =
        if kind == :top,
          do: {Camera.scale(up, -hu), Camera.scale(up, hu)},
          else: {Camera.scale(up, hu), Camera.scale(up, -hu)}

      {g0, g1} = grade(kind)
      k = block.exposure * lighting(normal, light)

      [
        %{
          id: "#{prefix}#{key}",
          d: path(camera, corners) <> "Z",
          from: at(camera, Camera.add(middle, first)),
          to: at(camera, Camera.add(middle, second)),
          stops: [{0, shade(base, k * g0)}, {1, shade(base, k * g1)}]
        }
      ]
    else
      []
    end
  end

  defp grade(:side), do: @side_grade
  defp grade(:top), do: @top_grade
  defp grade(:bottom), do: @bottom_grade

  @doc """
  A beam from one point to another: its path, how wide it is drawn (wider the
  nearer it is), and the gradient from one end's colour to the other's, each
  quieted toward the theme's beam tone and taking the far colour by its depth.
  """
  def beam(camera, {a, b}, {head, tail}, id) do
    near = distance(camera, a)
    far = distance(camera, b)
    arm = Camera.sub(camera.eye, camera.target)

    %{
      d: path(camera, [a, b]),
      width: Float.round(@beam_width * :math.sqrt(Camera.dot(arm, arm)) / ((near + far) / 2), 2),
      gradient: %{
        id: id,
        from: at(camera, a),
        to: at(camera, b),
        stops: [{0, beam_colour(head, near)}, {1, beam_colour(tail, far)}]
      }
    }
  end

  defp beam_colour(colour, depth) do
    colour
    |> mix("var(--lab-blocks-beam-tone)", @beam_share)
    |> fogged(depth)
  end

  defp fogged(colour, depth), do: mix(colour, "var(--lab-blocks-far)", 1 - fog(depth))

  @doc """
  A colour at brightness `k`: darker below one, toward white above it, as
  `color-mix` in sRGB, which is how the GPU picture mixes too.
  """
  def shade(base, k) when k <= 1, do: mix(base, "#000", k)
  def shade(base, k), do: mix(base, "#fff", 2 - min(k, 2))

  # `share` of `base`, the rest of `other`.
  defp mix(base, other, share) do
    percent = Float.round(share * 100, 1)
    if percent >= 100, do: base, else: "color-mix(in srgb, #{base} #{percent}%, #{other})"
  end

  @doc "A point on the stage, rounded for the page."
  def at(camera, point) do
    {x, y, _depth} = Camera.project(camera, point)
    {Float.round(x * 1.0, 2), Float.round(y * 1.0, 2)}
  end

  @doc "A polyline through these points, as an SVG path."
  def path(camera, points) do
    [{x, y} | rest] = Enum.map(points, &at(camera, &1))
    "M#{x} #{y}" <> Enum.map_join(rest, "", fn {x, y} -> "L#{x} #{y}" end)
  end

  @doc "How far a point is from the camera along its view."
  def distance(camera, point), do: camera |> Camera.project(point) |> elem(2)

  @doc "The box round a block's projected corners, as `{left, top, right, bottom}` in %."
  def hull_box(camera, block) do
    {xs, ys} = block |> corners() |> Enum.map(&at(camera, &1)) |> Enum.unzip()
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  @doc "The outline of a block on the stage, its convex hull, as points in %."
  def hull(camera, block), do: block |> corners() |> Enum.map(&at(camera, &1)) |> convex_hull()

  defp corners(block) do
    {hx, hy, hz} = block.half
    [ax, ay, az] = block.axes

    for sx <- [-1, 1], sy <- [-1, 1], sz <- [-1, 1] do
      block.center
      |> Camera.add(Camera.scale(ax, sx * hx))
      |> Camera.add(Camera.scale(ay, sy * hy))
      |> Camera.add(Camera.scale(az, sz * hz))
    end
  end

  # The convex hull of points on the stage (Andrew's monotone chain).
  defp convex_hull(points) do
    sorted = points |> Enum.uniq() |> Enum.sort()
    Enum.drop(chain(sorted), -1) ++ Enum.drop(chain(Enum.reverse(sorted)), -1)
  end

  defp chain(points) do
    points
    |> Enum.reduce([], fn point, hull -> [point | pop(hull, point)] end)
    |> Enum.reverse()
  end

  defp pop([b, a | rest] = hull, point) do
    if turn(a, b, point) <= 0, do: pop([a | rest], point), else: hull
  end

  defp pop(hull, _point), do: hull

  defp turn({ax, ay}, {bx, by}, {cx, cy}), do: (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end
