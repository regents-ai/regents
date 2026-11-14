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
  itself: a side from its top edge down, a top from its back edge forward. A
  block is drawn in its own colour, and each face it shows takes its shading as
  white or black laid over that colour, which is the same sRGB mix the GPU
  picture makes. Every product's block is turned the same way and the crown's
  all face the camera, so a kind of face shades alike on every block, and each
  shade is drawn once for all of them. A product far away takes a little of
  the tunnel's far colour, so depth reads in colour as well as in size; the
  crown is lit and keeps its own. Colours are CSS colours, so a block or beam
  whose colour follows the theme shades as well.
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
  Each product's block as the camera sees it, the farthest first: its `:node`;
  its `:colour`, far colour and all; its `:outline`, drawn in that colour; and
  each face it shows, as a path with the name of the shade laid over it
  (`:faces`). A block is a map of `:center`, `:half` (half its size along each
  of its `:axes`), `:base` (its colour), `:exposure` (how much brighter than
  the light alone it is drawn) and `:node` (the place it is).
  """
  def solids(blocks, camera) do
    blocks
    |> Enum.sort_by(&(-distance(camera, &1.center)))
    |> Enum.map(fn block ->
      %{
        node: block.node,
        colour: fogged(block.base, distance(camera, block.center)),
        outline: polygon(hull(camera, block)),
        faces:
          for face <- faces(block),
              Camera.facing(camera, face.normal, face.middle) > @edge_on do
            %{d: polygon(Enum.map(face.corners, &at(camera, &1))), shade: shade(block, face)}
          end
      }
    end)
  end

  @doc """
  The crown's blocks as the camera sees them. Only their fronts show, and they
  face the view at one depth, so every front is the same rectangle (`:size`,
  `{width, height}`) with the same shade over it (`:shade`), and each block is
  that rectangle at its own corner, with its `:t` (`:cells`, each a map of
  `:x`, `:y` and `:t`). Corners keep a hundredth of a percent, so the crown's
  gaps stay even.
  """
  def crown([first | _] = blocks, camera) do
    {_x, _y, width, height} = front_box(first, camera)

    %{
      size: {num(width), num(height)},
      shade: shade(first, front(first)),
      cells:
        Enum.map(blocks, fn block ->
          {x, y, _width, _height} = front_box(block, camera)
          %{x: num(x), y: num(y), t: block.t}
        end)
    }
  end

  defp front(block), do: Enum.find(faces(block), &(&1.key == "z+"))

  # The box round a block's front on the stage, `{left, top, width, height}`.
  defp front_box(block, camera) do
    {xs, ys} =
      block
      |> front()
      |> Map.fetch!(:corners)
      |> Enum.map(fn corner ->
        {x, y, _depth} = Camera.project(camera, corner)
        {x, y}
      end)
      |> Enum.unzip()

    {Enum.min(xs), Enum.min(ys), Enum.max(xs) - Enum.min(xs), Enum.max(ys) - Enum.min(ys)}
  end

  @doc """
  Every shade a face can take, by name: the white or black it lays over the
  face's colour at its first edge and at its second (`:stops`, each
  `{offset, {colour, opacity}}`), and where those edges run across the box
  round the face (`:from` and `:to`, as shares of that box), so one shade fits
  every face of its kind. The edges are those of a block of each kind at the
  middle of the view.
  """
  def shades(blocks, camera, light) do
    for block <- Enum.uniq_by(blocks, &is_nil(&1.node)),
        face <- faces(%{block | center: camera.target}),
        into: %{} do
      {first, second} = grade(face.kind)
      k = block.exposure * lighting(face.normal, light)

      {from, to} =
        face.corners
        |> Enum.map(fn corner ->
          {x, y, _depth} = Camera.project(camera, corner)
          {x, y}
        end)
        |> across_box()

      {shade(block, face),
       %{from: from, to: to, stops: [{0, over(k * first)}, {1, over(k * second)}]}}
    end
  end

  # A face's shade is named by the kind of block and which face it is.
  defp shade(block, face), do: if(block.node, do: "p", else: "c") <> face.key

  # A block's six faces: each one's outward normal, its middle, its kind and
  # key, and its corners, round from its first edge's two ends to its second's.
  defp faces(block) do
    {hx, hy, hz} = block.half
    [ax, ay, az] = block.axes

    for {normal, h, up, hu, across, ha, kind, key} <- [
          {ax, hx, ay, hy, az, hz, :side, "x+"},
          {Camera.scale(ax, -1), hx, ay, hy, az, hz, :side, "x-"},
          {az, hz, ay, hy, ax, hx, :side, "z+"},
          {Camera.scale(az, -1), hz, ay, hy, ax, hx, :side, "z-"},
          {ay, hy, az, hz, ax, hx, :top, "y+"},
          {Camera.scale(ay, -1), hy, az, hz, ax, hx, :bottom, "y-"}
        ] do
      middle = Camera.add(block.center, Camera.scale(normal, h))

      corner = fn u, a ->
        middle |> Camera.add(Camera.scale(up, u * hu)) |> Camera.add(Camera.scale(across, a * ha))
      end

      # A side runs from its top edge down; a top from its back edge forward.
      {first, second} = if kind == :top, do: {-1, 1}, else: {1, -1}

      %{
        normal: normal,
        middle: middle,
        kind: kind,
        key: key,
        corners: [corner.(first, 1), corner.(first, -1), corner.(second, -1), corner.(second, 1)]
      }
    end
  end

  defp grade(:side), do: @side_grade
  defp grade(:top), do: @top_grade
  defp grade(:bottom), do: @bottom_grade

  # Where a face's first and second edges run across the box round it: from the
  # first edge's middle, square to the two edges, to the second's line.
  defp across_box(points) do
    {xs, ys} = Enum.unzip(points)
    {left, top} = {Enum.min(xs), Enum.min(ys)}
    {width, height} = {Enum.max(xs) - left, Enum.max(ys) - top}

    [{ax, ay}, {bx, by}, {cx, cy}, {dx, dy}] =
      Enum.map(points, fn {x, y} -> {(x - left) / width, (y - top) / height} end)

    {ex, ey} = {bx - ax + cx - dx, by - ay + cy - dy}
    length = :math.sqrt(ex * ex + ey * ey)
    {nx, ny} = {-ey / length, ex / length}
    {fx, fy} = {(ax + bx) / 2, (ay + by) / 2}
    reach = ((cx + dx) / 2 - fx) * nx + ((cy + dy) / 2 - fy) * ny

    {{Float.round(fx, 3), Float.round(fy, 3)},
     {Float.round(fx + nx * reach, 3), Float.round(fy + ny * reach, 3)}}
  end

  # Brightness `k` as black or white laid over a colour, `{colour, opacity}`:
  # the same as mixing the colour toward black or white in sRGB.
  defp over(k) when k <= 1, do: {"#000", Float.round(1 - k, 3)}
  defp over(k), do: {"#fff", Float.round(min(k, 2) - 1, 3)}

  @doc """
  The transform that lays a line from 0 to 1 along the stage from one point to
  another, as CSS writes it. A beam and a line are each drawn as that one line,
  so each stage only moves it, and a beam's gradient runs along it on every stage.
  """
  def along(camera, a, b) do
    {x, y} = at(camera, a)
    {x1, y1} = at(camera, b)
    {dx, dy} = {x1 - x, y1 - y}
    "matrix(#{Enum.map_join([dx, dy, -dy, dx, x, y], ",", &num/1)})"
  end

  @doc "How wide a beam between two points is drawn, in CSS pixels: wider the nearer it is."
  def beam_width(camera, a, b) do
    arm = Camera.sub(camera.eye, camera.target)

    num(
      @beam_width * :math.sqrt(Camera.dot(arm, arm)) /
        ((distance(camera, a) + distance(camera, b)) / 2)
    )
  end

  @doc """
  A beam's colour where it meets a block: the block's own, quieted toward the
  theme's beam tone and taking the far colour by the block's depth.
  """
  def beam_colour(block, camera) do
    block.base
    |> mix("var(--lab-blocks-beam-tone)", @beam_share)
    |> fogged(distance(camera, block.center))
  end

  defp fogged(colour, depth), do: mix(colour, "var(--lab-blocks-far)", 1 - fog(depth))

  # `share` of `base`, the rest of `other`, as `color-mix` in sRGB, which is how
  # the GPU picture mixes too.
  defp mix(base, other, share) do
    percent = Float.round(share * 100, 1)
    if percent >= 100, do: base, else: "color-mix(in srgb,#{base} #{num(percent)}%,#{other})"
  end

  @doc "A point on the stage, to a tenth of a percent, as the page draws it."
  def at(camera, point) do
    {x, y, _depth} = Camera.project(camera, point)
    {Float.round(x * 1.0, 1), Float.round(y * 1.0, 1)}
  end

  @doc "A number as the page writes it: to two places, and a whole one without them."
  def num(value) do
    rounded = Float.round(value * 1.0, 2)
    whole = trunc(rounded)
    if rounded == whole, do: Integer.to_string(whole), else: Float.to_string(rounded)
  end

  @doc "A polyline through these points, as an SVG path."
  def path(camera, points) do
    [{x, y} | rest] = Enum.map(points, &at(camera, &1))
    "M#{num(x)} #{num(y)}" <> Enum.map_join(rest, fn {x, y} -> "L#{num(x)} #{num(y)}" end)
  end

  # A closed shape through these stage points, each step taken from the last.
  defp polygon([{x, y} | _] = points) do
    steps =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map_join(" ", fn [{x0, y0}, {x1, y1}] -> "#{num(x1 - x0)} #{num(y1 - y0)}" end)

    String.replace("M#{num(x)} #{num(y)}l#{steps}z", " -", "-")
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
