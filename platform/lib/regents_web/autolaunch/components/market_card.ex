defmodule RegentsWeb.Autolaunch.Components.MarketCard do
  @moduledoc """
  The home page's auctions and tokens, as autolaunch.sh's market cards and
  list rows draw them, from stored records alone.

  Every figure is shown in its auction's own currency: the dollar prices
  autolaunch.sh reads from the market are not here yet, which is how its cards
  read while it has none, and always on a test network. What bidders have put
  in shows in dollars where the record holds that figure. The Bid, Buy, Claim
  and Refund presses are the wallet's and come with it.
  """
  use Phoenix.Component

  import RegentsWeb.Autolaunch.Components.LinkIcon
  import RegentsWeb.Autolaunch.Components.MinimumWarning

  alias Regents.Autolaunch.{AuctionFigures, Lab, StoredImage, Token}
  alias Regents.Autolaunch.Robinhood.Lab, as: RobinhoodLab
  alias RegentsWeb.Autolaunch.Components.{BidPlaced, ChainIcon, CreatorLabel}
  alias RegentsWeb.Autolaunch.{Paths, TokenDisplay}

  @own_sites ["autolaunch.sh", "regents.sh"]

  # What each auction figure means, on the list's headings and the gallery's figures.
  @tips %{
    fdv:
      "What the whole token supply is worth at the price bidders pay right now. It rises as bids push the price up.",
    volume: "Everything bidders have put in so far."
  }

  attr :kind, :atom, required: true, values: [:auction, :token]
  attr :record, :map, required: true
  attr :creator_connections, :map, default: %{}
  attr :lead, :boolean, default: false, doc: "the page's first picture, which loads first"

  @doc """
  A gallery card. Every card reads, top to bottom: its ticker over its
  currency with its chain, its name, its price and one more figure, the
  creator's links.

  An auction's card shows only its clearing price up top, then its figures
  (on a Revstake auction the bid volume on hover or keyboard focus; the FDV
  always), Details, and a thin bar of how much of the auction's time has
  passed. The minimum is named only in an auction's last 30 minutes, and only
  while its bids are short of it. A token's card shows its price and market
  cap, then Details.
  """
  def explore_card(%{kind: :auction} = assigns) do
    figures = figures(assigns.record)

    assigns =
      assign(assigns,
        view: view(:auction, assigns.record, assigns.creator_connections),
        figures: figures,
        bar: time_bar(assigns.record, figures)
      )

    ~H"""
    <.auction_card
      view={@view}
      figures={@figures}
      bar={@bar}
      lead={@lead}
      raise?={@record.kind == :agent}
    />
    """
  end

  def explore_card(%{kind: :token} = assigns) do
    view = view(:token, assigns.record, assigns.creator_connections)

    assigns =
      assign(assigns,
        view: view,
        market_cap: money(assigns.record.market_cap, view.metric.unit) || "No price yet"
      )

    ~H"""
    <article
      class={["home-coin", @view.color && "home-coin--tinted"]}
      style={tint(@view.color)}
    >
      <.card_head view={@view} lead={@lead} />
      <div class="home-coin__metric">
        <TokenDisplay.price amount={@view.metric.amount} unit={@view.metric.unit} /><span>Price</span>
      </div>
      <p class="home-coin__figure">Market cap: <span>{@market_cap}</span></p>
      <.card_links view={@view} />
      <div class="home-coin__actions">
        <.link
          navigate={@view.path}
          class="rg-button rg-button--secondary home-coin__action"
          aria-label={"Details for #{@view.name}"}
        >Details</.link>
      </div>
    </article>
    """
  end

  attr :view, :map, required: true
  attr :figures, :map, required: true
  attr :bar, :map, required: true
  attr :raise?, :boolean, default: false, doc: "a Revstake auction, which shows its bid volume"
  attr :lead, :boolean, default: false

  defp auction_card(assigns) do
    ~H"""
    <article
      class={["home-coin", @view.color && "home-coin--tinted"]}
      style={tint(@view.color)}
    >
      <.card_head view={@view} lead={@lead} />
      <div class="home-coin__metric">
        <TokenDisplay.price amount={@view.metric.amount} unit={@view.metric.unit} /><span>Clearing price</span>
      </div>
      <.card_links view={@view} />
      <div class="home-coin__figures">
        <div :if={@raise?} class="home-coin__raise">
          <p>
            <span>Bid volume</span>
            <Regent.Primitives.tip id={"volume-#{@figures.id}"}>
              <:figure>{@figures.volume}</:figure>
              {tip(:volume)}
            </Regent.Primitives.tip>
            <.minimum_warning id={"short-#{@figures.id}"} from={@figures.short_from}>
              · below minimum
            </.minimum_warning>
          </p>
        </div>
        <p class="home-coin__floor">
          <span class="visually-hidden">FDV </span><Regent.Primitives.tip id={"fdv-#{@figures.id}"}>
            <:figure>{@figures.fdv}</:figure>
            {tip(:fdv, @figures.unit)}
          </Regent.Primitives.tip>
        </p>
      </div>
      <div class="home-coin__actions">
        <.link
          navigate={@view.path}
          class="rg-button rg-button--secondary home-coin__action"
          aria-label={"Details for #{@view.name}"}
        >Details</.link>
      </div>
      <div
        id={"time-bar-#{@figures.id}"}
        class={["home-coin__time", "home-coin__time--#{String.downcase(@view.chain)}"]}
        role="img"
        aria-label={@bar.label}
        title={@bar.label}
        phx-hook=".AuctionTimeBar"
        data-opens-at={@bar.opens_at && DateTime.to_iso8601(@bar.opens_at)}
        data-ends-at={@figures.ends_at && DateTime.to_iso8601(@figures.ends_at)}
      >
        <span :if={@bar.progress} style={"width: #{@bar.progress}%"}></span>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AuctionTimeBar">
        export default {
          mounted() { this.tick() },
          updated() { this.tick() },
          destroyed() { clearTimeout(this.timer) },
          tick() {
            clearTimeout(this.timer)
            if (!this.el.dataset.endsAt) return
            const end = Date.parse(this.el.dataset.endsAt)
            const open = Date.parse(this.el.dataset.opensAt)
            const minutes = Math.max(Math.floor((end - Date.now()) / 60000), 0)
            const d = Math.floor(minutes / 1440)
            const rest = `${Math.floor((minutes % 1440) / 60)}h ${minutes % 60}m`
            const label = minutes === 0 ? "Live, ending" : `Live, ${d > 0 ? `${d}d ${rest}` : rest} left`
            this.el.setAttribute("aria-label", label)
            this.el.title = label
            const fill = this.el.firstElementChild
            if (fill && open < end) {
              fill.style.width = `${Math.min(Math.max((Date.now() - open) / (end - open), 0), 1) * 100}%`
            }
            this.timer = setTimeout(() => this.tick(), 1000 - (Date.now() % 1000))
          }
        }
      </script>
    </article>
    """
  end

  attr :auction, :map, required: true
  attr :rank, :integer, required: true

  @doc """
  One square in the home page's "Bid volume" row: the token's picture with its
  rank, its name and ticker, what bidders have put in and its state in words.
  It opens the auction's page.
  """
  def backed_card(assigns) do
    view = view(:auction, assigns.auction, %{})

    assigns =
      assign(assigns,
        view: view,
        picture: StoredImage.sized(view.image, 640),
        volume: volume(assigns.auction),
        status: state_label(assigns.auction.state)
      )

    ~H"""
    <.link navigate={@view.path} class="home-backed__card">
      <span class="home-backed__art">
        <img
          :if={@picture}
          src={@picture}
          srcset={StoredImage.choices(@view.image)}
          sizes="(max-width: 42rem) calc(40vw - 32px), 320px"
          alt=""
          loading={@rank > 1 && "lazy"}
          fetchpriority={@rank == 1 && "high"}
          decoding="async"
          width="320"
          height="320"
        />
        <span :if={!@picture} aria-hidden="true">{String.first(@view.name || "?")}</span>
        <span class="home-backed__rank"><span class="visually-hidden">Rank </span>{@rank}</span>
      </span>
      <span class="home-backed__name">
        <strong>{@view.name}</strong>
        <small>{@view.symbol}</small>
      </span>
      <span class="home-backed__figures">
        <span>{@volume} raised</span>
        <span>{@status}</span>
      </span>
    </.link>
    """
  end

  attr :view, :map, required: true
  attr :lead, :boolean, required: true

  # The card's top, which opens its page: the image, the ticker over its
  # currency with the chain's box, and the name.
  defp card_head(assigns) do
    assigns =
      assign(
        assigns,
        :pair,
        Enum.join([assigns.view.symbol | List.wrap(assigns.view.metric.unit)], " / ")
      )

    ~H"""
    <.link navigate={@view.path} class="home-coin__main">
      <.coin_art view={@view} lead={@lead} />
      <p class="home-coin__pair">
        <span class="home-coin__ticker" title={@pair}>{@view.symbol}<span :if={@view.metric.unit}> /<wbr /> {@view.metric.unit}</span></span>
        <ChainIcon.chain_chip chain={@view.chain} label={chain_short(@view.chain)} />
      </p>
      <h2 class="home-coin__name">{@view.name}</h2>
    </.link>
    """
  end

  attr :view, :map, required: true

  defp card_links(assigns) do
    assigns =
      assign(assigns, :wallet, assigns.view.creator_address && wallet_link(assigns.view))

    ~H"""
    <div class="home-coin__links">
      <.card_socials connections={@view.connections} website={@view.website} wallet={@wallet} />
    </div>
    """
  end

  # The time bar is empty before an auction opens and full once it has
  # ended. A live auction whose opening time is unknown shows no fill.
  defp time_bar(%{state: :created}, figures),
    do: %{progress: 0, opens_at: nil, label: figures.status}

  defp time_bar(%{state: :active} = auction, %{ends_at: %DateTime{}} = figures) do
    label =
      if figures.status == "Ending", do: "Live, ending", else: "Live, #{figures.status} left"

    %{progress: figures.progress, opens_at: auction.opened_at, label: label}
  end

  defp time_bar(%{state: :active}, figures),
    do: %{progress: nil, opens_at: nil, label: figures.status}

  defp time_bar(_auction, figures), do: %{progress: 100, opens_at: nil, label: figures.status}

  attr :view, :map, required: true
  attr :lead, :boolean, required: true

  defp coin_art(assigns) do
    assigns = assign(assigns, :picture, StoredImage.sized(assigns.view.image, 640))

    ~H"""
    <div class="home-coin__art">
      <img
        :if={@picture}
        src={@picture}
        srcset={StoredImage.choices(@view.image)}
        sizes="(max-width: 22rem) calc(100vw - 76px), (max-width: 42rem) calc(50vw - 47px), 320px"
        alt={"#{@view.name} token"}
        loading={!@lead && "lazy"}
        fetchpriority={@lead && "high"}
        decoding="async"
        width="320"
        height="320"
      />
      <span :if={!@picture} class="home-coin__fallback" aria-label="No token image">{String.first(
        @view.name || "?"
      )}</span>
    </div>
    """
  end

  attr :records, :list, required: true, doc: "auctions with `fdv` loaded"
  attr :creators, :map, required: true, doc: "the creators' connected accounts, by account id"
  attr :loading, :boolean, default: false

  @doc """
  The auctions list: the token with its creator and age, then its price, what
  bidders have put in, its market cap and its status. Between the token and
  its price, a graduated auction shows a Buy link to its token's page while
  the row is pointed at. On a phone each row shows one figure instead of the
  price, raise and market cap: what bidders have put in while the auction can
  still take bids, its price once it has finished.
  """
  def auction_list(assigns) do
    ~H"""
    <div class="market-list__scroll">
      <table class="market-list__table market-list__table--auctions">
        <caption class="visually-hidden">Auctions</caption>
        <thead>
          <tr>
            <th scope="col">Token</th>
            <th scope="col"><span class="visually-hidden">Buy or take your bid</span></th>
            <th scope="col">Price</th>
            <th scope="col">
              Raised
              <Regent.Primitives.tip id="auctions-volume" label="About raised">
                {tip(:volume)}
              </Regent.Primitives.tip>
            </th>
            <th scope="col">
              Market cap
              <Regent.Primitives.tip id="auctions-fdv" label="About market cap">
                {tip(:fdv)}
              </Regent.Primitives.tip>
            </th>
            <th scope="col">Status</th>
            <th scope="col" class="market-list__key">
              <span class="visually-hidden">Raised so far, or the price once finished</span>
            </th>
          </tr>
        </thead>
        <tbody>
          <.auction_list_row
            :for={record <- @records}
            view={view(:auction, record, connections_for(record, @creators))}
            figures={figures(record)}
          />
          <tr
            :for={index <- 1..6}
            :if={@loading && @records == []}
            id={"auctions-loading-#{index}"}
            class="market-list__skeleton"
            aria-hidden="true"
          >
            <td colspan="7"><span class="loading-block"></span></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp tip(figure), do: Map.fetch!(@tips, figure)

  # A figure shown in its own currency says why it is not in dollars.
  defp tip(figure, nil), do: tip(figure)

  defp tip(figure, unit),
    do:
      "#{tip(figure)} There is no dollar price for #{unit} right now, so it is shown in #{unit}."

  # A row is handed only what it shows, so a reread that changes nothing shown,
  # such as the site's own note of when it last checked an auction, sends the
  # page nothing for that row.
  attr :view, :map, required: true
  attr :figures, :map, required: true

  defp auction_list_row(assigns) do
    ~H"""
    <tr class="market-list__row">
      <.list_token
        name={@view.name}
        symbol={@view.symbol}
        unit={@view.metric.unit}
        image={@view.image}
        chain={@view.chain}
        path={@view.path}
        detail={byline(@view)}
      />
      <td class="market-list__quick">
        <.link
          :if={@view.token_path}
          navigate={@view.token_path}
          class="rg-button rg-button--secondary market-list__buy"
          aria-label={"Buy #{@view.name}"}
        ><span class="rg-button__label">Buy</span></.link>
      </td>
      <td>
        <TokenDisplay.price amount={@view.metric.amount} unit={@view.metric.unit} />
      </td>
      <td>
        {@figures.volume}
        <.minimum_warning
          id={"short-#{@figures.id}"}
          from={@figures.short_from}
          tag="small"
        >
          Below minimum
        </.minimum_warning>
      </td>
      <td>{@figures.fdv}</td>
      <td class="market-list__status">
        <.status_figure figures={@figures} chain={@view.chain} />
      </td>
      <td class="market-list__key">
        <span :if={@figures.state in [:graduated, :failed]}>
          <small>Price</small>
          <TokenDisplay.price amount={@view.metric.amount} unit={@view.metric.unit} />
        </span>
        <span :if={@figures.state not in [:graduated, :failed]}>
          <small>Raised</small> {@figures.volume}
        </span>
      </td>
    </tr>
    """
  end

  # Who made it and how long ago, under a list row's name.
  defp byline(view),
    do:
      [view.creator && "by #{view.creator}", view.age]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

  attr :records, :list, required: true, doc: "launched tokens with `market_cap` loaded"
  attr :creators, :map, required: true, doc: "the creators' connected accounts, by account id"
  attr :loading, :boolean, default: false

  @doc """
  The tokens list: the token with its creator and when it launched, then its
  price and market cap. On a phone the market cap is left out.
  """
  def token_list(assigns) do
    ~H"""
    <div class="market-list__scroll">
      <table class="market-list__table market-list__table--tokens">
        <caption class="visually-hidden">Tokens</caption>
        <thead>
          <tr>
            <th scope="col">Token</th>
            <th scope="col">Price</th>
            <th scope="col">Market cap</th>
          </tr>
        </thead>
        <tbody>
          <.token_list_row
            :for={token <- @records}
            token={token}
            connections={connections_for(token, @creators)}
          />
          <tr
            :for={index <- 1..6}
            :if={@loading && @records == []}
            id={"tokens-loading-#{index}"}
            class="market-list__skeleton"
            aria-hidden="true"
          >
            <td colspan="3"><span class="loading-block"></span></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :token, :map, required: true
  attr :connections, :map, required: true

  defp token_list_row(assigns) do
    view = view(:token, assigns.token, assigns.connections)

    assigns =
      assign(assigns,
        view: view,
        market_cap: money(assigns.token.market_cap, view.metric.unit) || "No price yet"
      )

    ~H"""
    <tr class="market-list__row">
      <.list_token
        name={@view.name}
        symbol={@view.symbol}
        unit={@view.metric.unit}
        image={@view.image}
        chain={@view.chain}
        path={@view.path}
        detail={byline(@view)}
      />
      <td>
        <TokenDisplay.price amount={@token.price_quote} unit={@view.metric.unit} />
      </td>
      <td>{@market_cap}</td>
    </tr>
    """
  end

  attr :name, :string, required: true
  attr :symbol, :string, required: true

  attr :unit, :string,
    default: nil,
    doc: "the currency the token is paired with, after its ticker"

  attr :image, :string, default: nil
  attr :chain, :string, required: true, values: ["Base", "Robinhood"]
  attr :path, :string, required: true, doc: "the token's or auction's page"
  attr :detail, :string, default: nil, doc: "a short line under the name, such as its creator"

  # The cell every list row starts with: the token's image with its chain's
  # badge, then its name and its ticker on one line, the ticker followed by its
  # paired currency when one is given, and `detail` under them when given. It
  # opens `path`.
  defp list_token(assigns) do
    assigns = assign(assigns, :picture, StoredImage.sized(assigns.image, 96))

    ~H"""
    <th scope="row">
      <.link navigate={@path} class="market-list__token">
        <span class="market-list__art">
          <img
            :if={@picture}
            src={@picture}
            alt=""
            loading="lazy"
            decoding="async"
            width="40"
            height="40"
          />
          <span :if={!@picture} aria-hidden="true">{String.first(@name || "?")}</span>
          <ChainIcon.chain_icon
            chain={if @chain == "Robinhood", do: :robinhood, else: :base}
            class="market-list__chain"
          />
        </span>
        <span class="market-list__label">
          <span class="market-list__name">
            <strong>{@name}</strong>
            <small>{@symbol}<span :if={@unit} class="token-pair__unit"> / {@unit}</span></small>
          </span>
          <small :if={present?(@detail)} class="market-list__detail">{@detail}</small>
        </span>
      </.link>
    </th>
    """
  end

  defp figures(auction) do
    unit = auction.quote_token_symbol

    %{
      fdv: money(auction.fdv, unit) || "No price yet",
      volume: volume(auction),
      unit: unit,
      short_from: AuctionFigures.minimum_warning_from(auction),
      progress: time_progress(auction),
      opens_at: live_open(auction),
      ends_at: live_end(auction),
      status: figure_status(auction),
      outcome: outcome(auction),
      state: auction.state,
      id: auction.id
    }
  end

  # Everything bidders put in: in dollars when the site has priced it, else in
  # the auction's currency.
  defp volume(auction) do
    dollars(auction.bid_volume_usd) || money(auction.bid_volume, auction.quote_token_symbol) ||
      "Not counted yet"
  end

  # An amount in its own currency; nil while the amount is not known.
  defp money(nil, _unit), do: nil
  defp money(%Decimal{} = amount, unit), do: String.trim("#{TokenDisplay.short(amount)} #{unit}")

  # A dollar figure, such as `$1,234.50` or `$0.0123`, as every Regent page writes one.
  defp dollars(nil), do: nil

  defp dollars(%Decimal{sign: -1, coef: coef} = value) when coef != 0,
    do: "-" <> dollars(%{value | sign: 1})

  defp dollars(value), do: "$" <> RegentFormat.amount(value)

  # How much of a live auction's time has passed, from its opening to its
  # estimated end, as a whole percent.
  defp time_progress(%{
         state: :active,
         opened_at: %DateTime{} = opened_at,
         estimated_end_at: %DateTime{} = end_at
       }) do
    total = DateTime.diff(end_at, opened_at)

    if total > 0,
      do:
        DateTime.utc_now()
        |> DateTime.diff(opened_at)
        |> Kernel.*(100)
        |> div(total)
        |> min(100)
        |> max(0)
  end

  defp time_progress(_auction), do: nil

  defp live_open(%{state: :active, opened_at: %DateTime{} = opened_at}), do: opened_at
  defp live_open(_auction), do: nil

  defp live_end(%{state: :active, estimated_end_at: %DateTime{} = end_at}), do: end_at
  defp live_end(_auction), do: nil

  defp figure_status(%{state: :active, estimated_end_at: %DateTime{} = end_at}),
    do: time_left(max(DateTime.diff(end_at, DateTime.utc_now()), 0))

  defp figure_status(%{state: :graduated} = auction), do: ended("Graduated", auction)
  defp figure_status(%{state: :failed} = auction), do: ended("Minimum not met", auction)
  defp figure_status(%{state: state}), do: state_label(state)

  # Days, hours and minutes, never seconds; the last minute reads "Ending".
  # The page's tickers write the same wording as the time runs down.
  defp time_left(seconds) when seconds < 60, do: "Ending"

  defp time_left(seconds) do
    days = div(seconds, 86_400)
    rest = "#{div(rem(seconds, 86_400), 3600)}h #{div(rem(seconds, 3600), 60)}m"
    if days > 0, do: "#{days}d #{rest}", else: rest
  end

  defp ended(label, %{estimated_end_at: %DateTime{} = end_at}),
    do: "#{label} #{ended_ago(end_at)}"

  defp ended(label, _auction), do: label

  # How a finished auction came out, as its bar's fill and the few words under
  # it: a full bar once graduated; no bar, only the words, when the minimum
  # was not met.
  defp outcome(%{state: :graduated}), do: %{fill: 100, label: "Graduated"}
  defp outcome(%{state: :failed}), do: %{fill: nil, label: "Minimum not met"}

  defp outcome(_auction), do: nil

  attr :id, :string, required: true
  attr :auction, :map, required: true

  @doc "The auctions list's status figure for one stored auction, outside the list."
  def auction_status(assigns) do
    auction = assigns.auction

    assigns =
      assign(assigns,
        figures: %{
          id: assigns.id,
          progress: time_progress(auction),
          opens_at: live_open(auction),
          ends_at: live_end(auction),
          status: figure_status(auction),
          outcome: outcome(auction),
          state: auction.state
        },
        chain: if(RobinhoodLab.chain?(auction.chain_id), do: "Robinhood", else: "Base")
      )

    ~H"""
    <.status_figure figures={@figures} chain={@chain} />
    """
  end

  attr :figures, :map, required: true
  attr :chain, :string, required: true, values: ["Base", "Robinhood"]

  # A live auction's time bar in its chain's colour over its time left, both
  # kept moving in the browser. A finished auction's outcome bar: full and
  # ticked once graduated, else filled as far as the minimum was met, with when
  # it ended on hover. Any other state's word. A live auction whose opening
  # time is unknown shows an empty bar.
  defp status_figure(assigns) do
    ~H"""
    <span
      :if={@figures.ends_at}
      id={"time-left-#{@figures.id}"}
      phx-hook=".AuctionTimeLeft"
      data-opens-at={@figures.opens_at && DateTime.to_iso8601(@figures.opens_at)}
      data-ends-at={DateTime.to_iso8601(@figures.ends_at)}
    >
      <span
        class={["auction-figures__time", "auction-figures__time--#{String.downcase(@chain)}"]}
        aria-hidden="true"
      >
        <span :if={@figures.progress} style={"width: #{@figures.progress}%"}></span>
      </span>
      <small>{@figures.status}</small>
    </span>
    <span
      :if={@figures.outcome}
      class="auction-outcome"
      data-state={@figures.state}
      title={@figures.status}
    >
      <span class="auction-figures__time" aria-hidden="true">
        <span :if={@figures.outcome.fill} style={"width: #{@figures.outcome.fill}%"}></span>
      </span>
      <small>
        <Regent.Icons.icon :if={@figures.state == :graduated} name="check" />{@figures.outcome.label}
      </small>
    </span>
    <span
      :if={!@figures.ends_at && !@figures.outcome}
      class="auction-state"
      data-state={@figures.state}
    >
      {@figures.status}
    </span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AuctionTimeLeft">
      export default {
        mounted() { this.tick() },
        updated() { this.tick() },
        destroyed() { clearTimeout(this.timer) },
        tick() {
          clearTimeout(this.timer)
          const end = Date.parse(this.el.dataset.endsAt)
          const open = Date.parse(this.el.dataset.opensAt)
          const minutes = Math.max(Math.floor((end - Date.now()) / 60000), 0)
          const d = Math.floor(minutes / 1440)
          const rest = `${Math.floor((minutes % 1440) / 60)}h ${minutes % 60}m`
          this.el.querySelector("small").textContent = minutes === 0 ? "Ending" : d > 0 ? `${d}d ${rest}` : rest
          const fill = this.el.querySelector(".auction-figures__time > span")
          if (fill && open < end) {
            fill.style.width = `${Math.min(Math.max((Date.now() - open) / (end - open), 0), 1) * 100}%`
          }
          this.timer = setTimeout(() => this.tick(), 1000 - (Date.now() % 1000))
        }
      }
    </script>
    """
  end

  defp chain_short("Robinhood"), do: "RH"
  defp chain_short("Base"), do: "Base"

  attr :connections, :list, required: true
  attr :website, :string, default: nil
  attr :wallet, :map, default: nil, doc: "the creator's wallet and its explorer page"

  # At most six links, each its kind's mark then its handle or site (the
  # wallet only its mark, with its address on hover), in this order: the
  # accounts, the website, then the wallet; any past six are left to the
  # coin's page. A website shows only as an ordinary web link; anything else
  # a launch recorded there is left off the card.
  defp card_socials(assigns) do
    connections =
      Enum.map(assigns.connections, fn connection ->
        %{
          icon: connection.kind,
          url: connection.url,
          text: connection.handle,
          label: "#{connection.label} #{connection.handle}",
          title: connection.handle,
          rel: "noopener noreferrer"
        }
      end)

    website =
      case web_link(assigns.website) do
        nil ->
          []

        link ->
          [
            %{
              icon: :web,
              url: link.url,
              text: link.label,
              label: nil,
              title: link.label,
              rel: "noopener noreferrer nofollow"
            }
          ]
      end

    wallet =
      case assigns.wallet do
        nil ->
          []

        wallet ->
          [
            %{
              icon: :wallet,
              url: wallet.url,
              text: nil,
              label: "Creator wallet #{wallet.short}",
              title: wallet.address,
              rel: "noopener noreferrer"
            }
          ]
      end

    assigns = assign(assigns, :links, Enum.take(connections ++ website ++ wallet, 6))

    ~H"""
    <div :if={@links != []} class="launchpad-card__socials" aria-label="Creator links">
      <a
        :for={link <- @links}
        href={link.url}
        title={link.title}
        aria-label={link.label}
        target="_blank"
        rel={link.rel}
      ><.link_icon kind={link.icon} /><span :if={link.text}>{link.text}</span></a>
    </div>
    """
  end

  defp wallet_link(%{creator_address: address, chain: chain}),
    do: %{
      address: address,
      short: RegentFormat.short_address(address),
      url: BidPlaced.address_url(if(chain == "Robinhood", do: :robinhood, else: :base), address)
    }

  # A stored auction on either chain. A Robinhood auction's bids are paid in
  # USDG.
  defp view(:auction, auction, connections) do
    %{
      name: auction.title,
      symbol: auction.token_symbol,
      image: auction.image,
      color: auction.image_color,
      website: auction.website,
      metric: metric(auction.current_clearing_price, auction.quote_token_symbol),
      path: Paths.auction(auction),
      token_path: if(auction.state == :graduated, do: Paths.token(auction)),
      creator: creator_text(auction, connections),
      creator_address: auction.creator_address,
      age: auction_age(auction),
      connections: connection_list(connections),
      chain: if(RobinhoodLab.chain?(auction.chain_id), do: "Robinhood", else: "Base")
    }
  end

  defp view(:token, %{auction: %{chain_id: chain_id} = auction} = token, connections) do
    if RobinhoodLab.chain?(chain_id) do
      %{
        base_token_view(token, connections)
        | metric: metric(token.price_quote, auction.quote_token_symbol),
          chain: "Robinhood"
      }
    else
      base_token_view(token, connections)
    end
  end

  defp base_token_view(token, connections) do
    presentation = Token.presentation(token)

    %{
      name: presentation.name,
      symbol: presentation.symbol,
      image: presentation.image,
      color: presentation.image_color,
      website: presentation.website,
      metric: metric(token.price_quote, entry_symbol(token.auction)),
      path: Paths.token(token.auction),
      creator: creator_text(token.auction, connections),
      creator_address: token.auction.creator_address,
      age: ago(Map.get(token, :graduated_at) || Map.get(token, :inserted_at)),
      connections: connection_list(connections),
      chain: "Base"
    }
  end

  # The currency a Base token's pool is entered with (the swap's own on
  # autolaunch.sh), or nil where it cannot be swapped here.
  defp entry_symbol(%{kind: :agent, chain_id: chain_id, quote_token_symbol: "REGENT"}) do
    if base_chain?(chain_id), do: "REGENT"
  end

  defp entry_symbol(%{
         kind: :stocks,
         chain_id: chain_id,
         quote_token_address: address,
         quote_token_symbol: symbol
       })
       when is_binary(address) and address != "" and is_binary(symbol) do
    if base_chain?(chain_id) and String.trim(symbol) != "", do: symbol
  end

  defp entry_symbol(_auction), do: nil

  defp base_chain?(chain_id), do: chain_id in [8453, Lab.chain_id()]

  defp creator_text(auction, connections) do
    case CreatorLabel.name(auction, connections) do
      %{text: text} -> text
      nil -> nil
    end
  end

  @doc "The connected accounts of the creator of a list's auction or token."
  def connections_for(%{creator_human_account_id: id}, creators) when is_integer(id),
    do: Map.get(creators, id, %{})

  def connections_for(%{auction: %{creator_human_account_id: id}}, creators)
      when is_integer(id),
      do: Map.get(creators, id, %{})

  def connections_for(_record, _creators), do: %{}

  # An auction state in the words the site uses: live means open for bidding.
  # The lists' figures also say when a finished auction ended
  # (`figure_status/1`).
  defp state_label(:created), do: "Opening soon"
  defp state_label(:active), do: "Live"
  defp state_label(:ended), do: "Waiting to finish"
  defp state_label(:graduated), do: "Graduated"
  defp state_label(:failed), do: "Minimum not met"

  # A card whose image has a known colour carries it for its border and
  # background.
  defp tint(nil), do: nil
  defp tint(color), do: "--image-color: #{color}"

  defp metric(amount, unit), do: %{amount: present(amount, nil), unit: present(unit, nil)}

  @doc """
  The accounts a creator connected and proved they own, each with its kind,
  label, handle and link, in the order X, Company X, ENS, GitHub. Only proved
  accounts are read (`Regents.Autolaunch.HomeMarket.creators/1`).
  """
  def connection_list(connections) when is_map(connections) do
    [:profile, :x, :company, :ens, :github]
    |> Enum.flat_map(&connection(&1, Map.get(connections, &1)))
    |> Enum.uniq_by(& &1.url)
  end

  def connection_list(_connections), do: []

  defp connection(key, %{username: name}) when is_binary(name) and name != "" do
    {kind, label, base, handle} =
      case key do
        :ens -> {:ens, "ENS", "https://app.ens.domains/", name}
        :github -> {:github, "GitHub", "https://github.com/", name}
        :company -> {:x, "Company X", "https://x.com/", "@" <> name}
        _ -> {:x, "X", "https://x.com/", "@" <> name}
      end

    [
      %{
        kind: kind,
        username: name,
        label: label,
        handle: handle,
        url: base <> URI.encode_www_form(name)
      }
    ]
  end

  defp connection(_key, _value), do: []

  # An auction the chain says has ended may have an estimated end a moment
  # ahead; it still reads as past.
  defp ended_ago(end_at) do
    now = DateTime.utc_now()
    RegentFormat.relative_time(Enum.min([end_at, now], DateTime), now)
  end

  defp ago(nil), do: nil
  defp ago(at), do: RegentFormat.relative_time(at, DateTime.utc_now())

  # Once its lifecycle says bidding is over an auction counts from its end;
  # before that, from when it was listed.
  defp auction_age(%{state: state, estimated_end_at: %DateTime{} = end_at})
       when state in [:ended, :graduated, :failed],
       do: "Ended #{ended_ago(end_at)}"

  defp auction_age(auction),
    do: ago(Map.get(auction, :inserted_at) || Map.get(auction, :opened_at))

  # A creator's website as a link and a short label, or nil when it is not an
  # ordinary web address or names this site or Regents.
  defp web_link(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        if own_site?(host), do: nil, else: %{url: URI.to_string(uri), label: website_label(uri)}

      _other ->
        nil
    end
  end

  defp web_link(_url), do: nil

  # A creator who names this site or Regents as their website has named no
  # website of their own.
  defp own_site?(host) do
    host = String.downcase(host)
    Enum.any?(@own_sites, &(host == &1 or String.ends_with?(host, "." <> &1)))
  end

  defp website_label(%URI{host: host, path: path}),
    do: String.trim_leading(host, "www.") <> String.trim_trailing(path || "", "/")

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp present(value, fallback), do: if(present?(value), do: value, else: fallback)
end
