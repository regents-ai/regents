defmodule RegentsWeb.Autolaunch.Components.BidPlaced do
  @moduledoc """
  What a bid panel shows once its bid is placed: the news, the transaction on
  the chain's explorer, the way on to the auction and the portfolio (each left
  out on its own page), and a window to share it on X
  (`RegentsWeb.Autolaunch.Components.ShareDialog`). The news takes focus when it
  appears, so it is read out and scrolled into view wherever the panel sits,
  and its tick draws itself in as the bid lands.

  The host component handles `share_opened` when the window opens, reads the
  bidder's X account from `Regents.Account.Accounts` (with legacy `XConnection`
  fallback), and follows linked-identity PubSub broadcasts so connecting X on
  `/account/connections` in a new tab updates the open Share dialog live.
  """
  use Phoenix.Component
  use RegentsWeb, :verified_routes

  alias Phoenix.LiveView.JS
  alias Regents.Account.Accounts
  alias RegentsWeb.Autolaunch.Components.ShareDialog

  @doc """
  The bidder's verified X account: prefers their `/account/connections` `:x`
  `LinkedIdentity` and falls back to any legacy verified `:profile` `XConnection`.
  """
  def x_account(nil), do: nil

  def x_account(actor) do
    linked_x =
      case Accounts.list_my_linked_identities(actor: actor) do
        {:ok, identities} -> Enum.find(identities, &(&1.provider == :x and present_username?(&1)))
        {:error, _unavailable} -> nil
      end

    linked_x || legacy_profile_x(actor)
  end

  defp legacy_profile_x(actor) do
    case Regents.Autolaunch.list_my_x_connections(actor: actor) do
      {:ok, connections} ->
        Enum.find(connections, &(&1.role == :profile and not is_nil(connected(&1))))

      {:error, _unavailable} ->
        nil
    end
  end

  defp present_username?(%{username: username}), do: is_binary(username) and username != ""
  defp present_username?(_other), do: false

  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :token_symbol, :string, required: true
  attr :chain, :atom, required: true, values: [:base, :robinhood]
  attr :hash, :string, default: nil, doc: "the bid transaction"
  attr :test_chain, :boolean, default: false
  attr :auction_path, :string, required: true
  attr :auction_url, :string, required: true
  attr :share_image, :string, required: true, doc: "the auction's share picture"
  attr :x_connection, :map, default: nil, doc: "the bidder's personal X connection"
  attr :x_enabled, :boolean, default: false

  attr :page, :atom,
    default: nil,
    values: [nil, :auction, :portfolio],
    doc: "the page the panel sits on, whose own link is left out"

  def bid_placed(assigns) do
    assigns = assign(assigns, :x_account, connected(assigns.x_connection))

    ~H"""
    <div class="bid-placed" role="status" tabindex="-1" phx-mounted={JS.focus()}>
      <p class="bid-placed__news">
        <RegentsWeb.Motion.tick id={@id <> "-tick"} phx-hook="MotionTick" /> Your bid on
        <span class="ticker">{@token_symbol}</span>
        is placed.
      </p>
      <p :if={@test_chain} class="bid-form__note">
        This was on a test network. Test assets have no real value.
      </p>
      <a
        :if={@hash && !@test_chain}
        href={transaction_url(@chain, @hash)}
        target="_blank"
        rel="noopener noreferrer"
      >
        View on {explorer(@chain)} ↗
      </a>

      <div class="bid-placed__actions">
        <.link :if={@page != :auction} navigate={@auction_path} class="rg-button rg-button--secondary">
          <span class="rg-button__label">View auction</span>
        </.link>
        <.link
          :if={@page != :portfolio}
          navigate={~p"/autolaunch/portfolio"}
          class="rg-button rg-button--secondary"
        >
          <span class="rg-button__label">View portfolio</span>
        </.link>
        <ShareDialog.share_dialog
          id={"#{@id}-share"}
          message={"Bidding #{@token_symbol} on autolaunch.sh #{@auction_url}"}
          image={@share_image}
          phx-click="share_opened"
          phx-target={@target}
        >
          <:account>
            <div
              :if={@x_account || @x_enabled}
              id={"#{@id}-x"}
              class="share-x__account"
            >
              <p :if={@x_account}>Connected as @{@x_account.username}</p>
              <div :if={!@x_account}>
                <p>Connect your X account to share from it.</p>
                <a
                  href={~p"/account/connections"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="rg-button rg-button--secondary"
                >
                  <span class="rg-button__label">Connect X</span>
                </a>
              </div>
            </div>
          </:account>
        </ShareDialog.share_dialog>
      </div>
    </div>
    """
  end

  @doc "The chain's explorer page for a transaction."
  def transaction_url(:base, hash), do: "https://basescan.org/tx/#{hash}"
  def transaction_url(:robinhood, hash), do: "https://robinhoodchain.blockscout.com/tx/#{hash}"

  @doc "The chain's explorer page for an address."
  def address_url(:base, address), do: "https://basescan.org/address/#{address}"

  def address_url(:robinhood, address),
    do: "https://robinhoodchain.blockscout.com/address/#{address}"

  @doc "The name of the chain's explorer."
  def explorer(:base), do: "Basescan"
  def explorer(:robinhood), do: "Blockscout"

  defp connected(%{verified_at: %DateTime{}, username: username} = connection)
       when is_binary(username) and username != "",
       do: connection

  defp connected(_connection), do: nil
end
