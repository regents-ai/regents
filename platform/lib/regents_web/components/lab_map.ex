defmodule RegentsWeb.Components.LabMap do
  @moduledoc """
  The lab map: the Overview hero's picture of how the products work together.

  Each product is a small dot in its colour with its name beside it, a link to
  where its value card goes. Sign-in with Agent sits apart, smaller and without
  a colour of its own. A thin line joins two of them wherever one is used with
  the other, and each line carries one sentence saying how.

  Pointing at a line, focusing it or tapping it lifts that line and its two ends,
  dims the rest and shows its sentence under the map; pointing at or focusing a
  dot lifts every line it has. Every line is a stop in the tab order, named by
  its two ends and its sentence. The `LabMap` hook (`assets/js/hooks/lab_map.ts`)
  draws the lines in, moves between those states and lays a slow glow behind the
  map on the GPU; without it the same map is all there, and still.

  Positions are percentages of the map's box across and down, so the lines meet
  the dots at every width. `:side` puts a name `left`, `right`, `above` or
  `below` its dot; `above-start`, `above-end`, `below-start` and `below-end`
  line it up with the dot's left or right edge instead of its middle.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true

  attr :products, :list,
    required: true,
    doc: "maps of `:name`, `:tint`, `:href`, `:x`, `:y` and `:side`"

  attr :sign_in, :map, required: true, doc: "`:name`, `:href`, `:x`, `:y` and `:side`"

  attr :links, :list,
    required: true,
    doc:
      "maps of `:from` and `:to` names and a `:sentence`, in drawing and tab order; a later line lies over an earlier one"

  def lab_map(assigns) do
    nodes = Map.new([assigns.sign_in | assigns.products], &{&1.name, &1})

    tints =
      assigns.products
      |> Map.new(&{&1.name, &1.tint})
      |> Map.put(assigns.sign_in.name, "var(--lab-map-quiet)")

    assigns = assign(assigns, nodes: nodes, tints: tints, links: Enum.with_index(assigns.links))

    ~H"""
    <div
      id={@id}
      class="lab-map"
      role="group"
      aria-label="Product map"
      phx-hook="LabMap"
      phx-update="ignore"
      phx-mounted={
        JS.ignore_attributes(["data-lab-map-ready", "data-lab-map-motion", "data-lab-map-pick"])
      }
    >
      <div class="lab-map__stage">
        <canvas class="lab-map__canvas" data-lab-map-canvas aria-hidden="true"></canvas>
        <.dot :for={product <- @products} node={product} tint={product.tint} />
        <.dot node={@sign_in} />
        <svg class="lab-map__lines">
          <defs>
            <linearGradient
              :for={{link, index} <- @links}
              id={"#{@id}-ink-#{index}"}
              gradientUnits="userSpaceOnUse"
              x1={"#{@nodes[link.from].x}%"}
              y1={"#{@nodes[link.from].y}%"}
              x2={"#{@nodes[link.to].x}%"}
              y2={"#{@nodes[link.to].y}%"}
              style={"--from: #{@tints[link.from]}; --to: #{@tints[link.to]}"}
            >
              <stop offset="0" class="lab-map__from" />
              <stop offset="1" class="lab-map__to" />
            </linearGradient>
          </defs>
          <g
            :for={{link, index} <- @links}
            class="lab-map__link"
            tabindex="0"
            role="img"
            aria-label={"#{link.from} and #{link.to}: #{link.sentence}"}
            data-link={index}
            data-from={link.from}
            data-to={link.to}
          >
            <line
              :for={part <- ~w(hit ring gap line ink)}
              class={"lab-map__#{part}"}
              x1={"#{@nodes[link.from].x}%"}
              y1={"#{@nodes[link.from].y}%"}
              x2={"#{@nodes[link.to].x}%"}
              y2={"#{@nodes[link.to].y}%"}
              pathLength="1"
              stroke={part == "ink" && "url(##{@id}-ink-#{index})"}
            />
          </g>
        </svg>
      </div>
      <div class="lab-map__caption" aria-hidden="true">
        <p class="lab-map__say" data-say="" data-shown>
          Pick a line to see how two products work together.
        </p>
        <p :for={{link, index} <- @links} class="lab-map__say" data-say={index}>
          <span class="lab-map__pair">{link.from} and {link.to}</span>
          {link.sentence}
        </p>
      </div>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :tint, :string, default: nil, doc: "the product's colour; Sign-in with Agent has none"

  # A product's dot goes where its value card goes: another site in a new tab, or
  # a page of this shell without leaving it.
  defp dot(assigns) do
    assigns =
      assign(assigns,
        away: String.starts_with?(assigns.node.href, "https://"),
        style:
          "--x: #{assigns.node.x}%; --y: #{assigns.node.y}%" <>
            if(assigns.tint, do: "; --tint: #{assigns.tint}", else: "")
      )

    ~H"""
    <a
      :if={@away}
      href={@node.href}
      target="_blank"
      rel="noopener noreferrer"
      class={["lab-map__node", !@tint && "lab-map__node--quiet"]}
      data-node={@node.name}
      data-side={@node.side}
      data-tint={@tint}
      style={@style}
    >
      <span class="lab-map__dot"></span>
      <span class="lab-map__name">{@node.name}</span>
      <span class="visually-hidden">, opens in a new tab</span>
    </a>
    <.link
      :if={!@away}
      patch={@node.href}
      class="lab-map__node"
      data-node={@node.name}
      data-side={@node.side}
      data-tint={@tint}
      style={@style}
    >
      <span class="lab-map__dot"></span>
      <span class="lab-map__name">{@node.name}</span>
    </.link>
    """
  end
end
