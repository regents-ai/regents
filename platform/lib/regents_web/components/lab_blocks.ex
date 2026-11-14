defmodule RegentsWeb.Components.LabBlocks do
  @moduledoc """
  The Overview hero's picture of how the products work together: each product a
  block floating at its own depth in a deep tunnel, the crown set into the
  tunnel's far wall, and a thin beam between two products wherever one is used
  with the other (`RegentsWeb.RegentOpsLive` lists them).

  The server draws the whole scene (`LabBlocks.Scene`, `LabBlocks.Still`): a
  still picture, each product's block and name as a link to where its card
  goes, and each beam as a stop in the tab order named by its two ends and its
  sentence. Pointing at a beam, focusing it or tapping it picks it and shows its
  sentence under the scene; pointing at or focusing a product lifts every beam
  it has. The `LabBlocks` hook (`assets/js/hooks/lab_blocks.ts`) brings the
  scene in once, moves between those states and draws the scene again on the
  GPU over the still picture, where a mouse turns the view a few degrees.
  Without WebGPU, or with less motion asked for, the still picture is the scene.

  The scene is composed twice, for a wide stage and a narrow one; the stage
  takes the one that fits it and its fixed shape, so every position here is a
  percentage of a stage of known proportions.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias RegentsWeb.Components.LabBlocks.{Scene, Still}

  @layouts [:wide, :narrow]

  attr :id, :string, required: true
  attr :products, :list, required: true, doc: "maps of `:name`, `:tint` and `:href`"
  attr :sign_in, :map, required: true, doc: "`:name` and `:href`"

  attr :links, :list,
    required: true,
    doc:
      "maps of `:from` and `:to` names and a `:sentence`, in tab order; a later beam takes the press where two cross"

  def hero(assigns) do
    places =
      Enum.map(
        assigns.products,
        &Map.merge(Map.take(&1, [:name, :tint, :href]), %{base: &1.tint})
      ) ++
        [
          Map.merge(Map.take(assigns.sign_in, [:name, :href]), %{
            tint: nil,
            base: "var(--lab-blocks-quiet)"
          })
        ]

    scenes = Map.new(@layouts, &{&1, Scene.compose(&1, places, assigns.links)})

    assigns =
      assign(assigns,
        layouts: @layouts,
        line_parts: for(layout <- @layouts, part <- ~w(hit ring gap core), do: {layout, part}),
        places: Enum.map(places, &place(&1, scenes)),
        lines: lines(assigns.links, scenes),
        art:
          Map.new(scenes, fn {layout, scene} ->
            {layout, art(scene, "#{assigns.id}-#{layout}")}
          end),
        aspects: Map.new(scenes, fn {layout, scene} -> {layout, scene.aspect} end),
        data:
          Jason.encode!(Map.new(scenes, fn {layout, scene} -> {layout, Scene.to_json(scene)} end))
      )

    ~H"""
    <div
      id={@id}
      class="lab-blocks"
      role="group"
      aria-label="Product map"
      phx-hook="LabBlocks"
      phx-update="ignore"
      phx-mounted={
        JS.ignore_attributes([
          "data-lab-blocks-ready",
          "data-lab-blocks-motion",
          "data-lab-blocks-pick"
        ])
      }
      data-scene={@data}
      style={"--wide: #{@aspects.wide}; --narrow: #{@aspects.narrow}"}
    >
      <div class="lab-blocks__stage">
        <svg
          class="lab-blocks__art"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          <g :for={layout <- @layouts} data-layout={layout}>
            <defs>
              <linearGradient
                :for={gradient <- @art[layout].gradients}
                id={gradient.id}
                gradientUnits="userSpaceOnUse"
                x1={elem(gradient.from, 0)}
                y1={elem(gradient.from, 1)}
                x2={elem(gradient.to, 0)}
                y2={elem(gradient.to, 1)}
              >
                <stop
                  :for={{offset, colour} <- gradient.stops}
                  offset={offset}
                  style={"stop-color: #{colour}"}
                />
              </linearGradient>
            </defs>
            <path
              :for={shape <- @art[layout].tunnel}
              d={shape.d}
              class={shape[:class]}
              style={paint(shape)}
            />
            <g
              :for={solid <- @art[layout].solids}
              :if={!solid.node}
              class="lab-blocks__solid lab-blocks__solid--crown"
            >
              <.faces faces={solid.faces} />
            </g>
            <path
              :for={beam <- @art[layout].beams}
              d={beam.d}
              class="lab-blocks__beam"
              style={"stroke: url(##{beam.gradient.id}); --beam: #{beam.width}px"}
              data-art-link={beam.index}
            />
            <g
              :for={solid <- @art[layout].solids}
              :if={solid.node}
              class="lab-blocks__solid"
              data-art-node={solid.node}
            >
              <.faces faces={solid.faces} />
            </g>
          </g>
        </svg>
        <canvas class="lab-blocks__canvas" data-lab-blocks-canvas aria-hidden="true"></canvas>
        <.place_link :for={place <- @places} place={place} />
        <svg class="lab-blocks__lines" viewBox="0 0 100 100" preserveAspectRatio="none">
          <g
            :for={line <- @lines}
            class="lab-blocks__link"
            tabindex="0"
            role="img"
            aria-label={"#{line.from} and #{line.to}: #{line.sentence}"}
            data-link={line.index}
            data-from={line.from}
            data-to={line.to}
          >
            <path
              :for={{layout, part} <- @line_parts}
              class={"lab-blocks__#{part}"}
              data-layout={layout}
              d={line.paths[layout]}
            />
          </g>
        </svg>
      </div>
      <div class="lab-blocks__caption" aria-hidden="true">
        <p class="lab-blocks__say" data-say="" data-shown>
          Pick a line to see how two products work together.
        </p>
        <p :for={line <- @lines} class="lab-blocks__say" data-say={line.index}>
          <span class="lab-blocks__pair">{line.from} and {line.to}</span>
          {line.sentence}
        </p>
      </div>
    </div>
    """
  end

  attr :faces, :list, required: true

  # A face fills and edges in its own gradient, so no seam shows between two faces.
  defp faces(assigns) do
    ~H"""
    <path
      :for={face <- @faces}
      d={face.d}
      class="lab-blocks__face"
      style={"fill: url(##{face.id}); stroke: url(##{face.id})"}
    />
    """
  end

  attr :place, :map, required: true

  # A product's block and name go where its value card goes: another site in a new
  # tab, or a page of this shell without leaving it. The link covers the stage and
  # takes no press itself; only its block and its name do.
  defp place_link(assigns) do
    assigns = assign(assigns, away: String.starts_with?(assigns.place.href, "https://"))

    ~H"""
    <a
      :if={@away}
      href={@place.href}
      target="_blank"
      rel="noopener noreferrer"
      class={["lab-blocks__place", !@place.tint && "lab-blocks__place--quiet"]}
      data-node={@place.name}
      data-tint={@place.tint}
      style={@place.style}
    >
      <span class="lab-blocks__block"></span>
      <span class="lab-blocks__name">{@place.name}</span>
      <span class="visually-hidden">, opens in a new tab</span>
    </a>
    <.link
      :if={!@away}
      patch={@place.href}
      class="lab-blocks__place"
      data-node={@place.name}
      data-tint={@place.tint}
      style={@place.style}
    >
      <span class="lab-blocks__block"></span>
      <span class="lab-blocks__name">{@place.name}</span>
    </.link>
    """
  end

  # Where a place's name and block sit in each layout, as custom properties: the
  # name's point and how it hangs from it, and the box round the block with the
  # block's outline inside that box.
  defp place(place, scenes) do
    vars =
      Enum.flat_map(scenes, fn {layout, scene} ->
        prefix = if layout == :wide, do: "w", else: "n"
        block = Enum.find(scene.blocks, &(&1.node == place.name))
        {left, top, right, bottom} = box = Still.hull_box(scene.camera, block)
        {x, y, hang} = hang(block.side, box)

        [
          "--#{prefix}x: #{x}%",
          "--#{prefix}y: #{y}%",
          "--#{prefix}t: #{hang}",
          "--#{prefix}l: #{left}%",
          "--#{prefix}u: #{top}%",
          "--#{prefix}w: #{Float.round(right - left, 2)}%",
          "--#{prefix}h: #{Float.round(bottom - top, 2)}%",
          "--#{prefix}c: polygon(#{outline(Still.hull(scene.camera, block), box)})"
        ]
      end)

    tint = if place.tint, do: ["--tint: #{place.tint}"], else: []
    Map.put(place, :style, Enum.join(tint ++ vars, "; "))
  end

  # A block's outline as percentages of the box round it.
  defp outline(points, {left, top, right, bottom}) do
    Enum.map_join(points, ", ", fn {x, y} ->
      "#{Float.round((x - left) / (right - left) * 100, 1)}% #{Float.round((y - top) / (bottom - top) * 100, 1)}%"
    end)
  end

  # A name's point on the edge of its block's box, and how it hangs from there.
  defp hang(side, {left, top, right, bottom}) do
    mid_x = Float.round((left + right) / 2, 2)
    mid_y = Float.round((top + bottom) / 2, 2)

    case side do
      "above" -> {mid_x, top, "translate(-50%, calc(-100% - 4px))"}
      "above-start" -> {left, top, "translate(0, calc(-100% - 4px))"}
      "above-end" -> {right, top, "translate(-100%, calc(-100% - 4px))"}
      "below" -> {mid_x, bottom, "translate(-50%, 4px)"}
      "below-start" -> {left, bottom, "translate(0, 4px)"}
      "below-end" -> {right, bottom, "translate(-100%, 4px)"}
      "left" -> {left, mid_y, "translate(calc(-100% - 6px), -50%)"}
      "right" -> {right, mid_y, "translate(6px, -50%)"}
    end
  end

  # Each line's path from one block's middle to the other's, in each layout.
  defp lines(links, scenes) do
    links
    |> Enum.with_index()
    |> Enum.map(fn {link, index} ->
      paths =
        Map.new(scenes, fn {layout, scene} ->
          {layout, Still.path(scene.camera, ends(scene, index))}
        end)

      Map.merge(link, %{index: index, paths: paths})
    end)
  end

  defp ends(scene, index) do
    {from, to} = Enum.at(scene.lines, index)
    [Enum.at(scene.blocks, from).center, Enum.at(scene.blocks, to).center]
  end

  # The still picture of one layout: the tunnel, every block as the camera sees
  # it, and the beams, with every gradient they fill with.
  defp art(scene, id) do
    solids = Still.solids(scene.crown ++ scene.blocks, scene.camera, scene.light, id)

    beams =
      scene.lines
      |> Enum.with_index()
      |> Enum.map(fn {{from, to}, index} ->
        colours = {Enum.at(scene.blocks, from).base, Enum.at(scene.blocks, to).base}

        scene.camera
        |> Still.beam(List.to_tuple(ends(scene, index)), colours, "#{id}-r#{index}")
        |> Map.put(:index, index)
      end)

    tunnel = Scene.tunnel(scene, id)

    %{
      tunnel: tunnel.shapes,
      solids: solids,
      beams: beams,
      gradients:
        tunnel.gradients ++ Enum.flat_map(solids, & &1.faces) ++ Enum.map(beams, & &1.gradient)
    }
  end

  defp paint(%{fill: fill}), do: "fill: #{fill}"
  defp paint(%{stroke: stroke}), do: "stroke: #{stroke}"
end
