defmodule RegentsWeb.Autolaunch.PublicDocuments do
  @moduledoc """
  Autolaunch's written pages, from the committed Markdown in
  `priv/autolaunch/public`: so far About and the Changelog. An agent that asks
  for `text/markdown` receives it at the page's own address, through the site's
  `RegentsWeb.PublicDocuments.document/1`; the page shows the same words as
  HTML. Never a signed-in page or an account. Also the title and description of
  every Autolaunch page the site's root document shows, a token's page's
  naming its token (`market_page/3`) or saying it shows none (`market_page/1`).
  """

  alias Regents.Autolaunch.LaunchActions, as: RevstakeLaunchActions
  alias Regents.Autolaunch.LaunchChain
  alias Regents.Autolaunch.Stocks.LaunchActions

  @directory Application.app_dir(:regents, "priv/autolaunch/public")
  @files Enum.map(~w(about changelog), &Path.join(@directory, &1 <> ".md"))
  for file <- @files, do: @external_resource(file)
  @sources Map.new(@files, &{Path.basename(&1, ".md"), File.read!(&1)})

  # Each written page's Markdown by its address.
  @documents %{
    "/autolaunch/about" => "about",
    "/autolaunch/changelog" => "changelog"
  }

  # Each page's browser-tab title and search description. A title names the
  # page alone; the site's root document adds " · Autolaunch" once, except on
  # the home page, whose title starts with Autolaunch's name.
  @pages %{
    "/autolaunch" =>
      {"Autolaunch · Back AI agents at a fair price",
       "Bid in token auctions where everyone pays the same price, then stake to earn stablecoins or onchain stocks."},
    "/autolaunch/how-it-works" =>
      {"How it works",
       "How the auction works, and the supply, trading fees and staking rewards for every Autolaunch token."},
    "/autolaunch/auctions" =>
      {"Auctions", "Every Revstake and Memestock auction on Autolaunch, live and graduated."},
    "/autolaunch/tokens" =>
      {"Tokens", "Every token launched through Autolaunch, on Base and Robinhood Chain."},
    "/autolaunch/about" =>
      {"About",
       "What Autolaunch does, how it differs, who uses it, the team behind it, key facts, common questions and how to reach us."},
    "/autolaunch/changelog" =>
      {"Changelog", "What changed on autolaunch.sh for people and agents, newest first."},
    "/autolaunch/docs" =>
      {"Documentation",
       "Public APIs, signed agent endpoints, and developer reference for Autolaunch."},
    "/autolaunch/agents" => {"Agents", "Connect your AI agent to Autolaunch."},
    "/autolaunch/privacy" =>
      {"Privacy Policy", "How Regents Labs handles information on Autolaunch."},
    "/autolaunch/terms" => {"Terms of Use", "Terms governing use of Autolaunch."},
    "/autolaunch/create" =>
      {"Create Memestock", "Launch a Memestock token auction on Base or Robinhood Chain."},
    "/autolaunch/agent-business" =>
      {"Launch Revstake", "Launch a Revstake AI agent token auction on Base."},
    "/autolaunch/stocks" =>
      {"Stocks", "Onchain stocks available for Autolaunch Memestock auctions."},
    "/autolaunch/portfolio" =>
      {"Portfolio", "Your Autolaunch bids, claims, refunds, and token positions."},
    "/autolaunch/regent" =>
      {"REGENT", "How REGENT connects to Autolaunch launches and staking rewards."},
    "/autolaunch/convert" => {"Convert fees", "Convert accumulated launch fees into REGENT."},
    "/autolaunch/stock/covered-call" =>
      {"Covered Calls", "Onchain covered calls on Base stock tokens."},
    "/autolaunch/stock/isolated-afters" =>
      {"Isolated Afters", "After-hours stock price exposure on Base."},
    "/autolaunch/earn" => {"Earn", "Lend USDC on Base through Autolaunch."}
  }

  @doc "Full absolute URL for `path` on this site."
  def url(path), do: RegentsWeb.Endpoint.url() <> path

  @doc "Whether `path` has a public Markdown representation."
  def markdown?(path), do: Map.has_key?(@documents, path)

  @doc "Site-wide schema.org structured data."
  def structured_data, do: RegentsWeb.PublicDocuments.structured_data()

  @doc "The skill guide markdown for Autolaunch agents."
  def skill_guide, do: RegentsWeb.PublicDocuments.skill()

  @doc "Structured data for a single auction page."
  def auction_data(_auction, _meta), do: structured_data()

  @doc "Structured data for a single token page."
  def token_data(_token, _meta), do: structured_data()

  @doc "The written page at `path` as `%{markdown: text}`, or nil for every other address."
  def document(path) do
    case @documents do
      %{^path => name} -> %{markdown: markdown(name)}
      _other -> nil
    end
  end

  @doc "Every address `document/1` answers."
  def paths, do: Map.keys(@documents)

  @doc """
  The `page_title` and `page_description` assigns the site's root document reads.
  Any other address, such as one the router reads as a page's but spelled
  differently, is a missing page.
  """
  def page(path) do
    case @pages do
      %{^path => {title, description}} ->
        [page_title: title, page_description: description]

      _other ->
        raise RegentsWeb.NotFoundError
    end
  end

  @token_description "A token launched through Autolaunch on Base, to trade and stake."

  @doc """
  The `page_title` and `page_description` of a token's page, the title naming
  its token, as in "First Bite (BITE) token", or "SANDY token" when the name is
  the ticker. A token's page has no written version.
  """
  def market_page(:token, name, ticker) do
    named = if same_name?(name, ticker), do: name, else: "#{name} (#{ticker})"
    [page_title: "#{named} token", page_description: @token_description]
  end

  def market_page(:auction, name, ticker) do
    named = if same_name?(name, ticker), do: name, else: "#{name} (#{ticker})"
    [page_title: "#{named} auction", page_description: "A token auction on Autolaunch."]
  end

  def market_page(:stock, name, ticker) do
    named = if same_name?(name, ticker), do: name, else: "#{name} (#{ticker})"
    [page_title: "#{named} stock", page_description: "Onchain stock launches on Autolaunch."]
  end

  def market_page(:auction_not_found),
    do: [page_title: "Auction not found", page_description: "A token auction on Autolaunch."]

  def market_page(:auction_unavailable),
    do: [page_title: "Auction unavailable", page_description: "A token auction on Autolaunch."]

  @doc """
  The `page_title` and `page_description` of a token's page that shows no
  token: "Token not found" once its address names none, "Token unavailable"
  when it could not be read.
  """
  def market_page(:token_not_found),
    do: [page_title: "Token not found", page_description: @token_description]

  def market_page(:token_unavailable),
    do: [page_title: "Token unavailable", page_description: @token_description]

  defp same_name?(name, ticker), do: String.downcase(name) == String.downcase(ticker || "")

  # About names this site's addresses (`{{origin}}`) and how long a new launch's
  # auction runs and how a new Memestock creator's tokens are released, in
  # words, from the launches' fixed schedules, as the pages say it.
  defp markdown("about") do
    Enum.reduce(
      [
        {"{{origin}}", RegentsWeb.PublicDocuments.url("")},
        {"{{revstake_auction}}",
         LaunchChain.time_estimate(:base, RevstakeLaunchActions.schedule().length)},
        {"{{memestock_auction_base}}",
         LaunchChain.time_estimate(:base, LaunchActions.schedule(:base).length)},
        {"{{memestock_auction_robinhood}}",
         LaunchChain.time_estimate(:robinhood, LaunchActions.schedule(:robinhood).length)},
        {"{{memestock_release_base}}", LaunchActions.release(:base)},
        {"{{memestock_release_robinhood}}", LaunchActions.release(:robinhood)}
      ],
      @sources["about"],
      fn {mark, words}, text -> String.replace(text, mark, words) end
    )
  end

  defp markdown(name), do: @sources[name]

  # A table keeps its roles when a phone shows its rows as cards, and the only
  # spans are the cells' column names (`label_cells/1`), which a screen reader
  # already has.
  @sanitize [
    tags: ~w(h1 h2 h3 p ul ol li strong em a code pre br table thead tbody tr th td span),
    tag_attributes: %{"a" => ["href"]},
    generic_attributes: [],
    url_schemes: ~w(http https mailto),
    url_relative: :deny,
    link_rel: "noopener noreferrer",
    set_tag_attribute_values: %{
      "table" => %{"role" => "table"},
      "thead" => %{"role" => "rowgroup"},
      "tbody" => %{"role" => "rowgroup"},
      "tr" => %{"role" => "row"},
      "th" => %{"role" => "columnheader"},
      "td" => %{"role" => "cell"},
      "span" => %{"aria-hidden" => "true"}
    }
  ]
  @markdown [extension: [table: true, inline_code_attributes: false]]

  @doc """
  A document's committed Markdown as sanitized HTML. On a wide screen a table
  sits in a box that scrolls sideways and can be reached from the keyboard to
  scroll it; under 768px each of its rows stands as a card
  (`assets/css/autolaunch/pages/facts.css`).
  """
  # The HTML is MDEx-sanitized from the committed public Markdown.
  # sobelow_skip ["XSS.Raw"]
  def html(markdown) do
    markdown
    |> MDEx.parse_document!(@markdown)
    |> MDEx.traverse_and_update(&label_cells/1)
    |> MDEx.to_html!(@markdown ++ [sanitize: @sanitize])
    |> String.replace(
      ~s(<table role="table">),
      ~s(<div class="document-table" role="region" aria-label="Table" tabindex="0"><table role="table">)
    )
    |> String.replace("</table>", "</table></div>")
    |> Phoenix.HTML.raw()
  end

  # Every cell starts with its column's name, shown only when the rows stand as cards.
  defp label_cells(%MDEx.Table{nodes: [%MDEx.TableRow{nodes: heads} = head | rows]} = table) do
    labels = Enum.map(heads, &cell_label/1)
    %{table | nodes: [head | Enum.map(rows, &label_row(&1, labels))]}
  end

  defp label_cells(node), do: node

  defp label_row(%MDEx.TableRow{nodes: cells} = row, labels),
    do: %{row | nodes: Enum.zip_with(cells, labels, &%{&1 | nodes: [&2 | &1.nodes]})}

  defp cell_label(%MDEx.TableCell{nodes: nodes}) do
    text = Enum.map_join(nodes, &Map.get(&1, :literal, ""))

    %MDEx.Raw{
      literal:
        "<span>#{text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}</span>"
    }
  end
end
