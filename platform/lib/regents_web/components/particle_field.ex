defmodule RegentsWeb.Components.ParticleField do
  @moduledoc """
  The particle field: grains that take the shape of a control, a Lucide icon, a
  brand mark or a drawing of the page's own, and fly from one shape to the next
  (the `ParticleField` hook). How many grains follows the canvas: 80,000 in the
  lab, a few thousand in the theme switch.

  The shape and the value are the whole of it. A shape is a control's name
  (`switch`, `ring`, `slider`, `bar`, `checkbox`, `radio`, `spinner`, or `steps:2`
  to `steps:8`), `icon:` and any Lucide name the design system ships, `mark:`
  and a mark in `priv/particle_marks`, or the name of a drawing in the slot, an
  `svg` marked `data-particle-source` (the theme switch's sun and moon). The
  value runs from 0 to 1: how far the
  switch, the ring or the slider has come, which step is lit, which radio is
  chosen. Changing either on the element, from the server or a script, changes
  the field.

  A control's real element is the slot. It sits in the field's box under the
  grains, takes every press and key, and is what a screen reader meets; the
  grains are hidden from it. An icon or a mark is the server's own drawing, read
  out as a picture. Wherever the grains are not drawn (no WebGPU, less motion
  asked for, forced colours) the real control or the drawing is the whole
  picture, flat and square. The page gives the field its size.

  The grains are flat ink in the field's colours unless `glow` asks for the
  lab's lit grains and the glow round them.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @mark_files :regents
              |> Application.app_dir("priv/particle_marks")
              |> Path.join("*.svg")
              |> Path.wildcard()
  for file <- @mark_files, do: @external_resource(file)

  # Each mark is drawn in square blocks: its view box and each block's attributes,
  # so the page draws it as ordinary elements.
  @marks Map.new(@mark_files, fn file ->
           source = File.read!(file)
           [_svg, view_box] = Regex.run(~r{<svg[^>]*viewBox="([^"]+)"}, source)

           blocks =
             for [_rect, attributes] <- Regex.scan(~r{<rect\s([^>]*?)\s*/>}, source) do
               for [_attribute, name, value] <- Regex.scan(~r{([\w-]+)="([^"]*)"}, attributes),
                   do: {name, value}
             end

           name = Path.basename(file, ".svg")
           {name, %{label: String.capitalize(name), view_box: view_box, blocks: blocks}}
         end)

  attr :id, :string, required: true

  attr :shape, :string,
    required: true,
    doc: "a control's name, `icon:<lucide name>` or `mark:<name>`"

  attr :value, :float, default: 0.0, doc: "from 0 to 1"
  attr :glow, :boolean, default: false, doc: "lit grains and their glow, as the lab draws them"

  attr :driven, :boolean,
    default: false,
    doc: "the hook of a control round the field drives it (the theme switch)"

  attr :class, :any, default: nil
  slot :inner_block, doc: "the real control under the grains"

  def particle_field(assigns) do
    ~H"""
    <div
      id={@id}
      class={["particle-field", @class]}
      phx-hook={!@driven && "ParticleField"}
      phx-mounted={JS.ignore_attributes(["data-particle-ready"])}
      data-particle-shape={@shape}
      data-particle-value={@value}
      data-particle-glow={@glow}
    >
      <div id={"#{@id}-stage"} class="particle-field__stage" phx-update="ignore" aria-hidden="true">
        <canvas data-particle-canvas></canvas>
      </div>
      <.picture :if={picture?(@shape)} shape={@shape} />
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp picture?("icon:" <> _name), do: true
  defp picture?("mark:" <> _name), do: true
  defp picture?(_control), do: false

  attr :shape, :string, required: true

  defp picture(%{shape: "icon:" <> name} = assigns) do
    assigns =
      assign(assigns, name: name, label: name |> String.replace("-", " ") |> String.capitalize())

    ~H"""
    <div class="particle-field__picture" role="img" aria-label={@label}>
      <Regent.Icons.icon name={@name} data-particle-source={@shape} />
    </div>
    """
  end

  defp picture(%{shape: "mark:" <> name} = assigns) do
    assigns = assign(assigns, :mark, Map.fetch!(@marks, name))

    ~H"""
    <div class="particle-field__picture" role="img" aria-label={@mark.label}>
      <svg
        viewBox={@mark.view_box}
        fill="currentColor"
        data-particle-source={@shape}
        aria-hidden="true"
        focusable="false"
      >
        <rect :for={block <- @mark.blocks} {block} />
      </svg>
    </div>
    """
  end
end
