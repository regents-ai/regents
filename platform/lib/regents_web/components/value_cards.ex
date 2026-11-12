defmodule RegentsWeb.Components.ValueCards do
  @moduledoc """
  Value cards: a row of cards taken from the template's value cards
  (`skills/vgpu-island/references/value-cards.md` in ash-template). The
  Overview's row has one card for each product; a product's page has that
  product's own six, as its site shows them, and Cloak's page the template's
  four Cloak cards.

  A card is dark in both themes. From the top: a square panel of small coloured
  glyphs that moves and follows a mouse, drawn on the GPU by the `ValueCard`
  hook (`assets/js/hooks/value_card.ts`); the product's name in its colour
  beside its place in the row; one line saying what the product is for; a
  sentence; and, under a dashed rule, where the card goes.

  A still frame of the same panel (`priv/static/images/value-cards/<id>.webp`,
  drawn by `npm run stills:value-cards`) is the picture until the panel has
  drawn, and stays where it cannot be: no WebGPU, no JavaScript, or a visitor
  who asked for less motion.

  Each card is a map:

    * `:id` - the panel's path in `assets/js/value_cards/panels/` without its
      `.ts`: `"blob"` for one of this site's own, `"patchbay/ask"` for one in a
      product's folder. The last part names the card in the row's ids
    * `:name` - the product's name, one or two words
    * `:headline` - one line, ending with a full stop
    * `:line` - one sentence
    * `:tint` - the colour the name takes, reading at 4.5:1 on the card
    * `:action` - two words for where the card goes
    * `:href` - another page of the app shell the row sits in, reached without
      leaving the shell, or another site's address, which opens in a new tab
  """

  use Phoenix.Component
  use RegentsWeb, :verified_routes

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "names the row for screen readers"
  attr :cards, :list, required: true

  def value_cards(assigns) do
    assigns = assign(assigns, :count, length(assigns.cards))

    ~H"""
    <ul id={@id} class="value-cards" aria-label={@label}>
      <li
        :for={{card, number} <- Enum.with_index(@cards, 1)}
        id={"#{@id}-#{Path.basename(card.id)}"}
        class="value-card"
        style={"--value-card-tint: #{card.tint}"}
        phx-hook="ValueCard"
        phx-mounted={JS.ignore_attributes(["data-value-card-ready"])}
        data-value-card={card.id}
      >
        <a
          :if={away?(card.href)}
          href={card.href}
          target="_blank"
          rel="noopener noreferrer"
          class="value-card__face"
        >
          <.face
            id={"#{@id}-#{Path.basename(card.id)}"}
            card={card}
            place={place(number, @count)}
            away
          />
        </a>
        <.link :if={!away?(card.href)} patch={card.href} class="value-card__face">
          <.face id={"#{@id}-#{Path.basename(card.id)}"} card={card} place={place(number, @count)} />
        </.link>
      </li>
    </ul>
    """
  end

  attr :id, :string, required: true
  attr :card, :map, required: true
  attr :place, :string, required: true
  attr :away, :boolean, default: false

  defp face(assigns) do
    ~H"""
    <div class="value-card__panel" aria-hidden="true">
      <img
        class="value-card__still"
        src={~p"/images/value-cards/#{Path.split(@card.id <> ".webp")}"}
        alt=""
        width="600"
        height="600"
        loading="lazy"
        decoding="async"
      />
      <div id={"#{@id}-stage"} class="value-card__stage" phx-update="ignore">
        <canvas data-value-card-canvas></canvas>
      </div>
    </div>
    <div class="value-card__words">
      <div class="value-card__meta">
        <p class="value-card__name">{@card.name}</p>
        <span class="value-card__place" aria-hidden="true">{@place}</span>
      </div>
      <p class="value-card__headline">{@card.headline}</p>
      <p class="value-card__line">{@card.line}</p>
      <p class="value-card__action">
        {@card.action}<span :if={@away} class="visually-hidden">, opens in a new tab</span>
        <Regent.Icons.icon
          name={if @away, do: "arrow-up-right", else: "arrow-right"}
          class="value-card__arrow"
        />
      </p>
    </div>
    """
  end

  defp away?(href), do: String.starts_with?(href, "https://")

  # A card's place in its row, as "01 / 06".
  defp place(number, count), do: "#{two(number)} / #{two(count)}"

  defp two(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
