defmodule RegentsWeb.Keyfleet.SearchLive do
  @moduledoc """
  A fleet's search, at `/search` under the fleet's address with the words in
  the address as `?q=`, drawn inside the fleet's page under its bar
  (`RegentsWeb.Keyfleet.FleetLive`), whose search box opens it. It lists what the
  reader may read that matches, newest first (`Regents.Keyfleet.Search`), each line
  linking to the page it is on, a notebook's on the fleet's notebook host
  by way of its sign-in step here;
  "Show more" adds the next page under them.
  """

  use RegentsWeb, :html

  import Regents.Keyfleet.Fleets.Rules, only: [grouped: 1]
  import Phoenix.LiveView, only: [push_patch: 2]

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.{Fleets, Search}
  alias RegentsWeb.Keyfleet.{SearchJSON, WorkspacePage}

  @doc "The fleet's search page, for `query` when it has words."
  def search_path(fleet_id, query \\ "") do
    case String.trim(query) do
      "" -> "#{Fleets.path(fleet_id)}/search"
      words -> "#{Fleets.path(fleet_id)}/search?" <> URI.encode_query(q: words)
    end
  end

  @doc "Reads the first page of matches for the address's `q`, as `actor`."
  def read(socket, %{"fleet_id" => fleet_id} = params, actor) do
    assign(socket, :search, first(fleet_id, words(params["q"]), actor))
  end

  defp words(query) when is_binary(query), do: String.trim(query)
  defp words(_none), do: ""

  defp first(fleet_id, "", _actor), do: %{fleet_id: fleet_id, query: "", state: :idle}

  defp first(fleet_id, query, actor) do
    case Search.page(fleet_id, query, nil, actor) do
      {:ok, %{matches: matches, cursor: cursor}} ->
        %{fleet_id: fleet_id, query: query, state: :found, matches: matches, cursor: cursor}

      {:error, :query} ->
        %{fleet_id: fleet_id, query: query, state: :refused}
    end
  end

  @doc """
  The search box sent: its words open the search page. "Show more": the next
  page goes under the matches on show.
  """
  def handle_event(
        "search",
        %{"q" => query},
        %{assigns: %{fleet: %{fleet_id: fleet_id}}} = socket
      )
      when is_binary(query),
      do: {:noreply, push_patch(socket, to: search_path(fleet_id, query))}

  def handle_event("search", _params, socket), do: {:noreply, socket}

  def handle_event(
        "search_more",
        _params,
        %{assigns: %{search: %{state: :found, cursor: cursor} = search}} = socket
      )
      when cursor != nil do
    {:ok, %{matches: more, cursor: next}} =
      Search.page(search.fleet_id, search.query, cursor, actor(socket))

    {:noreply, assign(socket, :search, %{search | matches: search.matches ++ more, cursor: next})}
  end

  def handle_event("search_more", _params, socket), do: {:noreply, socket}

  defp actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: Human.for_account(account)

  defp actor(_socket), do: nil

  attr :search, :map, required: true, doc: "the search as `read/3` reads it"

  def results(assigns) do
    ~H"""
    <article id="search-page" class="search-page">
      <section class="search-panel" aria-labelledby="search-title">
        <h2 id="search-title">Search</h2>

        <Regent.Primitives.empty_state
          :if={@search.state == :idle}
          id="search-idle"
          class="kf-empty"
          title="Search this fleet’s rooms, messages, workspace and notebooks."
        />

        <Regent.Primitives.empty_state
          :if={@search.state == :refused}
          id="search-refused"
          class="kf-empty"
          title={"Search for at least one word, up to #{Search.max_query()} characters."}
        />

        <Regent.Primitives.empty_state
          :if={@search.state == :found and @search.matches == []}
          id="search-none"
          class="kf-empty"
          title={"Nothing matches “#{@search.query}”."}
        />

        <ol
          :if={@search.state == :found and @search.matches != []}
          id="search-matches"
          class="search-matches"
        >
          <li :for={match <- @search.matches} id={dom_id(match)} data-kind={match.kind}>
            <.link {to(@search.fleet_id, match)} class="search-match">
              <span class="search-match__head">
                <span class="search-match__kind">{kind(match)}</span>
                <span class="search-match__place">{place(match)}</span>
                <RegentsWeb.Keyfleet.Time.local
                  id={dom_id(match) <> "-at"}
                  at={match.at}
                  as={:moment}
                  class="search-match__at"
                />
              </span>
              <span class="search-match__words">{match.match}</span>
            </.link>
          </li>
        </ol>

        <Regent.Primitives.button
          :if={@search.state == :found and @search.cursor != nil}
          id="search-more"
          type="button"
          variant="secondary"
          arrow={false}
          phx-click="search_more"
        >
          Show more
        </Regent.Primitives.button>
      </section>
    </article>
    """
  end

  defp dom_id(%{kind: kind, id: id}), do: "search-#{kind}-" <> String.replace(id, "#", "-")

  # A notebook opens on the fleet's notebook host, through the step here that
  # signs its reader in there (`RegentsWeb.Keyfleet.NotebookOpenController`); every
  # other match opens here.
  defp to(fleet_id, %{kind: "notebook", url: url}) do
    to = URI.encode_query(to: URI.parse(url).path)
    %{href: "/keyfleet/fleets/#{fleet_id}/notebooks/open?" <> to}
  end

  defp to(fleet_id, match), do: %{patch: SearchJSON.path(fleet_id, match)}

  defp kind(%{kind: "post"}), do: "Post"
  defp kind(%{kind: "dm"}), do: "Message"
  defp kind(%{kind: "notebook"}), do: "Notebook"

  defp kind(%{kind: "item", type: type}),
    do: type |> WorkspacePage.type_name() |> elem(0) |> String.capitalize()

  defp place(%{kind: "post", room: %{name: name}}), do: name
  defp place(%{kind: "post", wall: token_id}), do: "Key #{grouped(token_id)}"
  defp place(%{kind: "dm", other_key: other}), do: "Key #{grouped(other)}"

  defp place(%{kind: kind, title: title})
       when kind in ["item", "notebook"] and is_binary(title) and title != "",
       do: title

  defp place(%{kind: kind, id: id}) when kind in ["item", "notebook"], do: id
end
