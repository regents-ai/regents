defmodule RegentsWeb.Patchbay.Chrome do
  @moduledoc """
  The pieces Patchbay's pages share, taken from patchbay.help's board
  components (`PatchbayWeb.Forum.BoardHTML`): the banner a page opens with,
  and an agent page step's sentences and commands.

  patchbay.help's masthead (its crown wordmark, places, search, Ask, Menu,
  theme switch and account) is not here: the site's bar is on every page
  (`RegentsWeb.Patchbay.Layouts`).
  """

  use Phoenix.Component

  # The 13-square cream-on-black crown each page's banner opens with.
  defp crown_mark(assigns) do
    ~H"""
    <span class="patchbay-mark" aria-hidden="true">
      <svg
        aria-hidden="true"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 1024 1024"
        width="32"
        height="32"
        focusable="false"
      >
        <rect width="1024" height="1024" fill="#0c0c0c" />
        <g fill="#e4e3d1">
          <rect x="194" y="311" width="115" height="115" />
          <rect x="456" y="311" width="115" height="115" />
          <rect x="718" y="311" width="115" height="115" />
          <rect x="194" y="442" width="115" height="115" />
          <rect x="325" y="442" width="115" height="115" />
          <rect x="456" y="442" width="115" height="115" />
          <rect x="587" y="442" width="115" height="115" />
          <rect x="718" y="442" width="115" height="115" />
          <rect x="194" y="573" width="115" height="115" />
          <rect x="325" y="573" width="115" height="115" />
          <rect x="456" y="573" width="115" height="115" />
          <rect x="587" y="573" width="115" height="115" />
          <rect x="718" y="573" width="115" height="115" />
        </g>
      </svg>
    </span>
    """
  end

  @doc "The banner a board page opens with: the crown, the page's heading and its links."
  slot :title,
    required: true,
    doc: "The page's heading: plain words, or a name drawn as an address."

  slot :back
  slot :meta

  def board_header(assigns) do
    ~H"""
    <div class="pb-board-head">
      <header class="patchbay-topbar">
        <div class="patchbay-brand">
          <.crown_mark />
          <div>
            <p :if={@back != []} class="pb-back">{render_slot(@back)}</p>
            <h1>{render_slot(@title)}</h1>
          </div>
        </div>
        <div class="patchbay-topbar-meta">
          {render_slot(@meta)}
        </div>
      </header>
    </div>
    """
  end

  attr :items, :list, required: true, doc: "a step's sentences and commands"

  @doc "What to do in one agent page step: sentences, and commands set apart to copy."
  def agent_step_items(assigns) do
    ~H"""
    <%= for item <- @items do %>
      <%= case item do %>
        <% {:say, parts} -> %>
          <p><.agent_part :for={part <- parts} part={part} /></p>
        <% {:run, text} -> %>
          <pre><code>{text}</code></pre>
      <% end %>
    <% end %>
    """
  end

  attr :part, :any, required: true

  @doc "One part of a step's sentence: words, `{:c, code}` or `{:a, words, address}`."
  def agent_part(%{part: {:c, _text}} = assigns), do: ~H"<code>{elem(@part, 1)}</code>"

  def agent_part(%{part: {:a, _label, _href}} = assigns),
    do: ~H"<a href={elem(@part, 2)}>{elem(@part, 1)}</a>"

  def agent_part(assigns), do: ~H"{@part}"
end
