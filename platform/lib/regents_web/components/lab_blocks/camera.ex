defmodule RegentsWeb.Components.LabBlocks.Camera do
  @moduledoc """
  Where a point of the Overview hero's scene lands on its stage.

  The camera stands at `:eye`, looks at `:target` with y overhead, sees `:fov`
  degrees from top to bottom and a stage of `:aspect` (width over height). A
  projected point is a percentage of the stage across and down, as the stage's
  names and lines are placed, and its distance along the view.

  `assets/js/lab_blocks/scene.ts` projects the same way for the GPU picture, so
  the two agree to the pixel.
  """

  @type vec :: {float, float, float}

  @doc "A camera, with the view's three directions worked out once."
  def new(eye, target, fov, aspect) do
    forward = normalize(sub(target, eye))
    right = normalize(cross(forward, {0.0, 1.0, 0.0}))

    %{
      eye: eye,
      target: target,
      fov: fov,
      aspect: aspect,
      forward: forward,
      right: right,
      up: cross(right, forward),
      tan: :math.tan(fov * :math.pi() / 360)
    }
  end

  @doc "A point as `{x %, y %, depth}` on the stage."
  def project(camera, point) do
    d = sub(point, camera.eye)
    depth = dot(d, camera.forward)
    nx = dot(d, camera.right) / (depth * camera.tan * camera.aspect)
    ny = dot(d, camera.up) / (depth * camera.tan)
    {(nx + 1) * 50, (1 - ny) * 50, depth}
  end

  @doc "The point at `{x %, y %}` on the stage, `depth` along the view."
  def unproject(camera, {x, y}, depth) do
    across = (x / 50 - 1) * depth * camera.tan * camera.aspect
    up = (1 - y / 50) * depth * camera.tan

    camera.eye
    |> add(scale(camera.right, across))
    |> add(scale(camera.up, up))
    |> add(scale(camera.forward, depth))
  end

  @doc """
  How squarely a face with this outward normal through this point faces the
  camera: 1 head on, 0 edge on, below 0 turned away.
  """
  def facing(camera, normal, point), do: dot(normal, normalize(sub(camera.eye, point)))

  @doc "What the GPU picture needs to project the same way, as plain lists."
  def to_json(camera) do
    %{
      eye: Tuple.to_list(camera.eye),
      target: Tuple.to_list(camera.target),
      fov: camera.fov,
      aspect: camera.aspect
    }
  end

  def add({a, b, c}, {x, y, z}), do: {a + x, b + y, c + z}
  def sub({a, b, c}, {x, y, z}), do: {a - x, b - y, c - z}
  def scale({a, b, c}, s), do: {a * s, b * s, c * s}
  def dot({a, b, c}, {x, y, z}), do: a * x + b * y + c * z
  def cross({a, b, c}, {x, y, z}), do: {b * z - c * y, c * x - a * z, a * y - b * x}

  def normalize(v), do: scale(v, 1 / :math.sqrt(dot(v, v)))
end
