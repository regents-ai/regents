defmodule RegentsWeb.PairLive do
  @moduledoc """
  The page a "Pair New Agent" link opens: `/pair?to=<path>`, where `to` is a
  page on this site. A person pairs their agent in the same pairing box as the
  pairing window's (`RegentsWeb.PairingBox`), and the message they paste ends by
  sending the agent to that page once it is paired. A link with no `to`, or one
  that is not a page on this site, opens plain pairing.
  """
  use RegentsWeb, :html
  import RegentsWeb.Components.PageHead, only: [page_head: 1, signed_out: 1]

  # A page on this site: one leading "/", never "//" or "/\", which browsers read
  # as another site, and no spaces or control characters.
  @page ~r|\A/(?![/\\])[^\s\\\x00-\x1f\x7f]{0,511}\z|u

  @doc "The page a pairing link names, or nil when it names none on this site."
  @spec start(map()) :: String.t() | nil
  def start(%{"to" => to}) when is_binary(to), do: if(to =~ @page, do: to)
  def start(_params), do: nil

  attr :account, :map, default: nil
  attr :lease, :any, required: true
  attr :start, :string, default: nil

  def page(assigns) do
    ~H"""
    <article id="pair-page" class="account-page pair-page">
      <.page_head title="Pair New Agent">
        <:tip>Pair your agent with your account, then send it the message.</:tip>
      </.page_head>
      <p :if={@start} id="pair-start">
        Once paired, it starts at <a href={@start}>{RegentsWeb.Endpoint.url() <> @start}</a>
      </p>
      <.signed_out :if={is_nil(@account)} id="pair-signed-out">
        Sign in to pair your agent.
      </.signed_out>
      <.live_component
        :if={@account}
        module={RegentsWeb.PairingBox}
        id="pair-pairing-box"
        lease={@lease}
        account={@account}
        start={@start}
      />
    </article>
    """
  end
end
