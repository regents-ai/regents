defmodule RegentsWeb.Autolaunch.PublicDocuments do
  @moduledoc """
  Autolaunch's written pages, from the committed Markdown in
  `priv/autolaunch/public`: so far About and the Changelog. An agent that asks
  for `text/markdown` receives it at the page's own address, through the site's
  `RegentsWeb.PublicDocuments.document/1`; the page shows the same words as
  HTML. Never a signed-in page or an account. Also the title and description of
  every Autolaunch page the site's root document shows.
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
    "/autolaunch/about" =>
      {"About",
       "What Autolaunch does, how it differs, who uses it, the team behind it, key facts, common questions and how to reach us."},
    "/autolaunch/changelog" =>
      {"Changelog", "What changed on autolaunch.sh for people and agents, newest first."}
  }

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
