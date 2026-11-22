defmodule RegentsWeb.Autolaunch.Components.LaunchTrust do
  @moduledoc """
  What a buyer can check about a launch. "Launch Creator": the launching
  wallet and the accounts its creator proved they own, which says who they
  are and nothing about the project's merits, with anything else they named,
  unchecked. Then the launch's contracts; a Memestock launch's paired stock is
  named with its issuer, chain and address. A token's page shows both
  (`token_facts/1`) and its launch type among its market figures
  (`launch_type/1`). Once the token's pool is read, the contracts end with the
  locker that holds its positions and the pool's id.
  """
  use Phoenix.Component

  alias Regents.Autolaunch.Lab
  alias RegentsWeb.Autolaunch.Components.{MarketCard, StockIdentity}

  attr :auction, :map, required: true, doc: "the launch's auction record"
  attr :connections, :map, required: true, doc: "the creator's connected accounts"
  attr :pool, :map, default: nil, doc: "the launched pool as read from the chain, once read"

  @doc """
  A launched token's facts on its own page: who launched it, then its
  contracts and its pool, each shortened with its copy icon and, for a
  contract, its arrow to the chain's explorer.
  """
  def token_facts(assigns) do
    auction = assigns.auction

    assigns =
      assign(assigns,
        address_chain: address_chain(auction),
        contracts: contracts(auction, assigns.pool)
      )

    ~H"""
    <div class="launch-trust token-facts">
      <.creator auction={@auction} connections={@connections} />

      <section aria-labelledby="token-contracts">
        <h2 id="token-contracts" class="token-page__title">Contracts</h2>
        <ul class="token-facts__list">
          <li :for={{{label, address}, index} <- Enum.with_index(@contracts)}>
            <span class="token-facts__label">{label}</span>
            <Regent.Primitives.address
              id={"token-facts-contract-#{index}"}
              address={address}
              chain={@address_chain}
            />
          </li>
          <li :if={paired_stock?(@auction)}>
            <span class="token-facts__label">Paired stock</span>
            <span>
              {@auction.quote_token_symbol}
              <StockIdentity.stock_identity
                id="token-facts-stock"
                chain={:base}
                address={@auction.quote_token_address}
                explorer={@address_chain}
              />
            </span>
          </li>
          <li :if={@pool}>
            <span class="token-facts__label">Pool</span>
            <Regent.Primitives.address
              id="token-facts-pool"
              address={@pool.pool_id}
              kind="id"
              chain={@address_chain}
            />
          </li>
        </ul>
      </section>
    </div>
    """
  end

  @doc "A launch's type, Revstake or Memestock."
  def launch_type(%{kind: :agent}), do: "Revstake"
  def launch_type(%{kind: :stocks}), do: "Memestock"

  attr :auction, :map, required: true
  attr :connections, :map, required: true

  # Who launched it: the launching wallet and the accounts its creator proved
  # they own, with anything else they named, unchecked.
  defp creator(assigns) do
    auction = assigns.auction

    assigns =
      assign(assigns,
        address_chain: address_chain(auction),
        wallet: auction.creator_address,
        accounts: accounts(assigns.connections),
        website: MarketCard.web_link(auction.website),
        telegram: named_link(auction.telegram),
        discord: named_link(auction.discord),
        links: Enum.flat_map(auction.links, &List.wrap(MarketCard.web_link(&1)))
      )

    ~H"""
    <section class="launch-trust__block" aria-labelledby="launch-trust-who">
      <h2 id="launch-trust-who">Launch Creator</h2>
      <dl class="launch-trust__rows">
        <div :if={@wallet}>
          <dt>Launch wallet</dt>
          <dd>
            <Regent.Primitives.address
              id="launch-trust-wallet"
              address={@wallet}
              chain={@address_chain}
            />
          </dd>
        </div>
        <div :for={{label, account} <- @accounts}>
          <dt>{label}</dt>
          <dd :if={account}>
            <a href={account.url} target="_blank" rel="noopener noreferrer">{account.handle}</a>
            <span class="launch-trust__checked">
              <span aria-hidden="true">✓</span> Ownership checked
            </span>
          </dd>
          <dd :if={!account} class="launch-trust__muted">Not connected</dd>
        </div>
        <div :if={@website}>
          <dt>Website</dt>
          <dd>
            <a href={@website.url} target="_blank" rel="noopener noreferrer nofollow">
              {@website.label}
            </a>
            <span class="launch-trust__muted">Named by the creator, not checked</span>
          </dd>
        </div>
        <div :for={{label, link} <- [{"Telegram", @telegram}, {"Discord", @discord}]} :if={link}>
          <dt>{label}</dt>
          <dd>
            <a href={link.url} target="_blank" rel="noopener noreferrer nofollow">{link.label}</a>
            <span class="launch-trust__muted">Named by the creator, not checked</span>
          </dd>
        </div>
        <div :for={link <- @links}>
          <dt>Link</dt>
          <dd>
            <a href={link.url} target="_blank" rel="noopener noreferrer nofollow">{link.label}</a>
            <span class="launch-trust__muted">Named by the creator, not checked</span>
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  # A Memestock launch names the stock token it is priced and paid in.
  defp paired_stock?(%{kind: :stocks, quote_token_address: address}), do: is_binary(address)
  defp paired_stock?(_auction), do: false

  # The chain `Regent.Primitives.address` opens the launch's addresses on; a local
  # test chain has no explorer.
  defp address_chain(auction), do: if(Lab.test_chain?(auction.chain_id), do: "test", else: "base")

  # A creator's Telegram group or Discord invite as a link, labelled by its
  # address without https://: only an https address with a host.
  defp named_link("https://" <> label = url) do
    case URI.new(url) do
      {:ok, %URI{host: host}} when host not in [nil, ""] -> %{url: url, label: label}
      _invalid -> nil
    end
  end

  defp named_link(_url), do: nil

  # Each account kind the creator could connect, with the matching accounts
  # or nil for a kind they have not connected; Company X only when there is one.
  defp accounts(connections) do
    connected = MarketCard.connection_list(connections)

    Enum.flat_map(["X", "Company X", "ENS", "GitHub"], fn label ->
      case {label, Enum.filter(connected, &(&1.label == label))} do
        {"Company X", []} -> []
        {label, []} -> [{label, nil}]
        {label, matching} -> Enum.map(matching, &{label, &1})
      end
    end)
  end

  # The launch's own contracts the record names, then the locker that holds
  # its pool position once the pool has been read.
  defp contracts(auction, pool) do
    treasury = if auction.kind == :agent, do: auction.treasury_address

    lockers =
      for %{locked?: true, owner: owner} <- (pool && pool.positions) || [],
          uniq: true,
          do: {"Locker", owner}

    Enum.filter(
      [
        {"Token", auction.token_address},
        {"Auction", auction.auction_address},
        {"Treasury", treasury}
      ],
      fn {_label, address} -> is_binary(address) end
    ) ++ lockers
  end
end
