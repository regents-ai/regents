defmodule RegentsWeb.Components.FleetFigure do
  @moduledoc """
  The home page's figure: a web of cards, the fleet, the apps it uses and
  REGENT staking, joined by labelled lines. Grey lines carry work out from
  the fleet; warm lines carry USDC to staking.

  Each card and each line's label sits at a point on the figure, given as
  percentages for the wide layout and the narrow one. The server draws the
  lines as a still picture. The `FleetFigure` hook draws them again with vgpu,
  flowing, and shows that picture once its first frame has landed; it reads
  every line's ends and bend back from where the cards and labels stand.
  """

  use Phoenix.Component

  alias RegentsWeb.ExampleWorkflows

  # Where each card sits, as {x, y} percentages of the figure: wide, then narrow.
  # Wide, the fleet stands on the left, staking on the right and the apps
  # between them; narrow, the apps stand around the fleet and staking below.
  @cards %{
    "keyfleet" => {{11, 50}, {50, 37}},
    "techtree" => {{36, 15}, {26, 11}},
    "patchbay" => {{64, 15}, {74, 11}},
    "autolaunch" => {{50, 85}, {26, 63}},
    "staking" => {{89, 50}, {72, 87}}
  }

  # What travels along each line, and where its bend pulls it, wide then
  # narrow. A line with no bend is straight.
  @lines [
    {"keyfleet", "techtree", "Ideas", nil, {32, 26}},
    {"keyfleet", "patchbay", "Blockers", {50.5, 47.5}, {68, 26}},
    {"keyfleet", "autolaunch", "Projects", nil, nil},
    {"keyfleet", "staking", "USDC", nil, nil},
    {"patchbay", "staking", "USDC", nil, {109, 51}},
    {"autolaunch", "staking", "USDC", nil, {31, 89}}
  ]

  attr :id, :string, default: "fleet-figure"

  def figure(assigns) do
    assigns =
      assign(assigns,
        cards: Enum.map(ExampleWorkflows.workflows(), &card/1),
        lines: Enum.map(@lines, &line/1)
      )

    ~H"""
    <figure
      id={@id}
      class="fleet-web"
      phx-hook="FleetFigure"
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["data-fleet-ready"])}
    >
      <div class="fleet-web__map">
        <div class="fleet-web__stage" phx-update="ignore" id={"#{@id}-stage"}>
          <svg
            class="fleet-web__still"
            viewBox="0 0 100 100"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <path
              :for={line <- @lines}
              class={"fleet-web__path fleet-web__path--#{line.kind}"}
              d={line.wide}
              vector-effect="non-scaling-stroke"
              data-layout="wide"
            />
            <path
              :for={line <- @lines}
              class={"fleet-web__path fleet-web__path--#{line.kind}"}
              d={line.narrow}
              vector-effect="non-scaling-stroke"
              data-layout="narrow"
            />
          </svg>
          <canvas class="fleet-web__canvas" data-fleet-canvas aria-hidden="true"></canvas>
        </div>
        <span
          :for={line <- @lines}
          class={"fleet-web__word fleet-web__word--#{line.kind}"}
          style={line.style}
          title={line.title}
          data-line={"#{line.from} #{line.to}"}
          data-kind={line.kind}
        >
          {line.word}
        </span>
        <a
          :for={card <- @cards}
          id={"#{@id}-#{card.id}"}
          href={card.href}
          class={"fleet-web__card fleet-web__card--#{card.id}"}
          style={card.style}
          data-card={card.id}
        >
          <span class="fleet-web__name">{card.name}</span>
          <span class="fleet-web__slogan">{card.label}</span>
        </a>
      </div>
      <figcaption class="visually-hidden">
        A fleet on Keyfleet sends ideas to Techtree, blockers to Patchbay and projects to
        Autolaunch. Keyfleet, Patchbay and Autolaunch send USDC to REGENT staking.
      </figcaption>
    </figure>
    """
  end

  defp card(%{id: id} = workflow) do
    workflow
    |> Map.take([:id, :name, :label])
    |> Map.merge(%{
      href: if(id == "staking", do: "#staking-actions", else: "/#{id}"),
      style: place(Map.fetch!(@cards, id))
    })
  end

  defp line({from, to, word, wide_bend, narrow_bend}) do
    {wide_from, narrow_from} = Map.fetch!(@cards, from)
    {wide_to, narrow_to} = Map.fetch!(@cards, to)
    wide = curve(wide_from, wide_to, wide_bend)
    narrow = curve(narrow_from, narrow_to, narrow_bend)
    kind = if to == "staking", do: :revenue, else: :work

    %{
      from: from,
      to: to,
      word: word,
      kind: kind,
      title: title(from, to),
      wide: path(wide),
      narrow: path(narrow),
      style: place({middle(wide), middle(narrow)})
    }
  end

  # The tip on a label: the full share behind a USDC line, or the work along a line.
  defp title(from, to),
    do: Enum.find(ExampleWorkflows.connections(), &(&1.from == from and &1.to == to)).label

  # A quadratic curve; one without a bend pulls from its own middle.
  defp curve({x1, y1} = from, {x2, y2} = to, nil), do: {from, {(x1 + x2) / 2, (y1 + y2) / 2}, to}
  defp curve(from, to, bend), do: {from, bend, to}

  defp middle({{x1, y1}, {cx, cy}, {x2, y2}}),
    do: {0.25 * x1 + 0.5 * cx + 0.25 * x2, 0.25 * y1 + 0.5 * cy + 0.25 * y2}

  # The still picture's box is 100 by 100 and stretched to the figure.
  defp path({{x1, y1}, {cx, cy}, {x2, y2}}),
    do: "M#{n(x1)} #{n(y1)} Q#{n(cx)} #{n(cy)} #{n(x2)} #{n(y2)}"

  defp place({{wx, wy}, {nx, ny}}),
    do: "--x: #{n(wx)}%; --y: #{n(wy)}%; --nx: #{n(nx)}%; --ny: #{n(ny)}%"

  defp n(value) when is_integer(value), do: Integer.to_string(value)
  defp n(value), do: value |> Float.round(2) |> :erlang.float_to_binary(decimals: 2)
end
