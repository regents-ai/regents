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
  percentage of a stage of known proportions. The still picture draws once what
  is the same on both: the tunnel and its side walls' seams, the shades the
  faces take, the crown, which the narrow stage scales, and each beam and line,
  which each stage lays where it runs there. Only the floor's and ceiling's
  seams and the products' blocks are drawn for each.

  What the page repeats for every block, beam and line it keeps short: those
  are found by their `data-` attributes rather than by a class, and their
  inline styles are written without spaces.
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
    # What is the same on every stage is taken from the wide one.
    wide = scenes.wide
    crown = Still.crown(wide.crown, wide.camera)

    blocks =
      Map.new(scenes, fn {layout, scene} -> {layout, Still.solids(scene.blocks, scene.camera)} end)

    {across, down} = Scene.crown_scale(wide, scenes.narrow)

    assigns =
      assign(assigns,
        layouts: @layouts,
        places: Enum.map(places, &place(&1, scenes)),
        lines: lines(assigns.links, scenes),
        tunnel: Scene.tunnel(wide),
        sides: Scene.seams(wide, [:left, :right]),
        seams:
          Map.new(scenes, fn {layout, scene} ->
            {layout, Scene.seams(scene, [:floor, :ceiling])}
          end),
        crown: crown,
        blocks: blocks,
        shades:
          shades(wide, [
            crown.shade
            | for(
                solids <- Map.values(blocks),
                solid <- solids,
                face <- solid.faces,
                do: face.shade
              )
          ]),
        ends:
          wide.blocks
          |> Enum.with_index(fn block, index ->
            "--e#{index}:#{Still.beam_colour(block, wide.camera)}"
          end)
          |> Enum.join(";"),
        stage:
          "--wide:#{wide.aspect};--narrow:#{scenes.narrow.aspect};--crown-narrow:#{across} #{down}",
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
      style={@stage}
    >
      <div class="lab-blocks__stage">
        <svg
          class="lab-blocks__art"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          aria-hidden="true"
          style={@ends}
        >
          <defs>
            <g id={"#{@id}-ring"} class="lab-blocks__ring">
              <path :for={ring <- @tunnel.ring} d={ring.d} style={"--step:#{ring.step}"} />
            </g>
            <linearGradient
              id={"#{@id}-fade"}
              class="lab-blocks__fade"
              gradientUnits="userSpaceOnUse"
            >
              <stop :for={{offset, share} <- @tunnel.fade} offset={offset} stop-opacity={share} />
            </linearGradient>
            <linearGradient
              :for={fade <- @tunnel.fades}
              id={"#{@id}-#{fade.wall}"}
              href={"##{@id}-fade"}
              x1={elem(fade.from, 0)}
              y1={elem(fade.from, 1)}
              x2={elem(fade.to, 0)}
              y2={elem(fade.to, 1)}
            />
            <linearGradient
              :for={{name, shade} <- @shades}
              id={"#{@id}-#{name}"}
              x1={elem(shade.from, 0)}
              y1={elem(shade.from, 1)}
              x2={elem(shade.to, 0)}
              y2={elem(shade.to, 1)}
            >
              <stop
                :for={{offset, {colour, opacity}} <- shade.stops}
                offset={offset}
                stop-color={colour}
                stop-opacity={opacity}
              />
            </linearGradient>
            <%!-- Each beam runs from its first end's colour to its second's. --%>
            <linearGradient id={"#{@id}-beam"} gradientUnits="userSpaceOnUse" x2="1" />
            <linearGradient
              :for={line <- @lines}
              id={"#{@id}-r#{line.index}"}
              href={"##{@id}-beam"}
              phx-no-format
            ><stop style={"stop-color:var(--e#{elem(line.ends, 0)})"} /><stop offset="1" style={"stop-color:var(--e#{elem(line.ends, 1)})"} /></linearGradient>
            <g id={"#{@id}-cell"} phx-no-format><rect
              :for={fill <- [nil, "url(##{@id}-#{@crown.shade})"]}
              width={elem(@crown.size, 0)}
              height={elem(@crown.size, 1)}
              fill={fill}
            /></g>
          </defs>
          <g transform="translate(50 50)">
            <use
              :for={{scale, k} <- Enum.with_index(@tunnel.rings)}
              href={"##{@id}-ring"}
              transform={"scale(#{scale})"}
              style={"--k:#{k}"}
            />
          </g>
          <path d={@tunnel.far} class="lab-blocks__far" />
          <g class="lab-blocks__seams">
            <path :for={{wall, d} <- @sides} d={d} stroke={"url(##{@id}-#{wall})"} />
            <g :for={layout <- @layouts} data-layout={layout}>
              <path :for={{wall, d} <- @seams[layout]} d={d} stroke={"url(##{@id}-#{wall})"} />
            </g>
          </g>
          <g class="lab-blocks__crown">
            <use
              :for={cell <- @crown.cells}
              href={"##{@id}-cell"}
              x={cell.x}
              y={cell.y}
              style={"--crown:#{Still.num(cell.t * 100)}%"}
            />
          </g>
          <line
            :for={line <- @lines}
            x2="1"
            style={"#{line.at};stroke:url(##{@id}-r#{line.index});--beam:#{line.width}px"}
            data-art-link={line.index}
          />
          <%!-- Shapes repeated for every block are written without space between them. --%>
          <g :for={layout <- @layouts} data-layout={layout} phx-no-format><g
            :for={solid <- @blocks[layout]}
            data-art-node={solid.node}
            style={"fill:#{solid.colour}"}
          ><.faces solid={solid} id={@id} /></g></g>
        </svg>
        <canvas class="lab-blocks__canvas" data-lab-blocks-canvas aria-hidden="true"></canvas>
        <.place_link :for={place <- @places} place={place} />
        <%!-- Each line is four lines in this order, which the stylesheet tells
          apart by place: a wide band nobody sees that takes the press, then the
          focus ring, its gap and the line along its middle. --%>
        <svg
          class="lab-blocks__lines"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          phx-no-format
        ><g
          :for={line <- @lines}
          tabindex="0"
          role="img"
          aria-label={"#{line.from} and #{line.to}: #{line.sentence}"}
          data-link={line.index}
          data-from={line.from}
          data-to={line.to}
          style={line.at}
        ><line :for={_part <- 1..4} x2="1" /></g></svg>
      </div>
      <div class="lab-blocks__caption" aria-hidden="true" phx-no-format><p data-say="" data-shown>Pick a line to see how two products work together.</p><p
        :for={line <- @lines}
        data-say={line.index}
      ><span>{line.from} and {line.to}</span>{line.sentence}</p></div>
    </div>
    """
  end

  attr :solid, :map, required: true
  attr :id, :string, required: true

  # A block in its own colour, which its group gives, and over each face it
  # shows, that face's shade; one outline under them all leaves no seam
  # between two faces.
  defp faces(assigns) do
    ~H"""
    <path d={@solid.outline} /><path
      :for={face <- @solid.faces}
      d={face.d}
      fill={"url(##{@id}-#{face.shade})"}
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
      style={@place.style}
    ><span class="lab-blocks__block"></span><span class="lab-blocks__name">{@place.name}</span><span class="visually-hidden">, opens in a new tab</span></a>
    <.link
      :if={!@away}
      patch={@place.href}
      class="lab-blocks__place"
      data-node={@place.name}
      style={@place.style}
    ><span class="lab-blocks__block"></span><span class="lab-blocks__name">{@place.name}</span></.link>
    """
  end

  # Where a place's name and block sit in each layout, as custom properties: the
  # name's point and how it hangs from it, and the box round the block with the
  # block's outline inside that box.
  defp place(place, scenes) do
    vars =
      Enum.flat_map(scenes, fn {layout, scene} ->
        prefix = prefix(layout)
        block = Enum.find(scene.blocks, &(&1.node == place.name))
        {left, top, right, bottom} = box = Still.hull_box(scene.camera, block)
        {x, y, hang} = hang(block.side, box)

        [
          "--#{prefix}x:#{Still.num(x)}%",
          "--#{prefix}y:#{Still.num(y)}%",
          "--#{prefix}t:#{hang}",
          "--#{prefix}l:#{Still.num(left)}%",
          "--#{prefix}u:#{Still.num(top)}%",
          "--#{prefix}w:#{Still.num(right - left)}%",
          "--#{prefix}h:#{Still.num(bottom - top)}%",
          "--#{prefix}c:polygon(#{outline(Still.hull(scene.camera, block), box)})"
        ]
      end)

    tint = if place.tint, do: ["--tint:#{place.tint}"], else: []
    Map.put(place, :style, Enum.join(tint ++ vars, ";"))
  end

  # A block's outline as whole percentages of the box round it.
  defp outline(points, {left, top, right, bottom}) do
    Enum.map_join(points, ",", fn {x, y} ->
      "#{round((x - left) / (right - left) * 100)}% #{round((y - top) / (bottom - top) * 100)}%"
    end)
  end

  # A name's point on the edge of its block's box, and how it hangs from there.
  defp hang(side, {left, top, right, bottom}) do
    mid_x = (left + right) / 2
    mid_y = (top + bottom) / 2

    case side do
      "above" -> {mid_x, top, "translate(-50%,calc(-100% - 4px))"}
      "above-start" -> {left, top, "translate(0,calc(-100% - 4px))"}
      "above-end" -> {right, top, "translate(-100%,calc(-100% - 4px))"}
      "below" -> {mid_x, bottom, "translate(-50%,4px)"}
      "below-start" -> {left, bottom, "translate(0,4px)"}
      "below-end" -> {right, bottom, "translate(-100%,4px)"}
      "left" -> {left, mid_y, "translate(calc(-100% - 6px),-50%)"}
      "right" -> {right, mid_y, "translate(6px,-50%)"}
    end
  end

  # Each link's line and beam, from one block's middle to the other's: the two
  # blocks it joins (`:ends`), how wide its beam is, and how it is laid on each
  # stage (`:at`, a transform for each). A block is as far away on both stages,
  # so a beam is as wide on both.
  defp lines(links, scenes) do
    %{wide: wide} = scenes

    Enum.with_index(links, fn link, index ->
      ends = Enum.at(wide.lines, index)

      at =
        Enum.map_join(scenes, ";", fn {layout, scene} ->
          {a, b} = middles(scene, ends)
          "--#{prefix(layout)}m:#{Still.along(scene.camera, a, b)}"
        end)

      {a, b} = middles(wide, ends)

      Map.merge(link, %{
        index: index,
        ends: ends,
        at: at,
        width: Still.beam_width(wide.camera, a, b)
      })
    end)
  end

  defp middles(scene, {from, to}),
    do: {Enum.at(scene.blocks, from).center, Enum.at(scene.blocks, to).center}

  defp prefix(:wide), do: "w"
  defp prefix(:narrow), do: "n"

  # The shades the faces drawn take, from their names.
  defp shades(scene, used) do
    (scene.crown ++ scene.blocks)
    |> Still.shades(scene.camera, scene.light)
    |> Map.take(used)
  end
end
