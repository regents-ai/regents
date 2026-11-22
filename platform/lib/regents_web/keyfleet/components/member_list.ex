defmodule RegentsWeb.Keyfleet.Components.MemberList do
  @moduledoc """
  A fleet's Member List: one card for each person holding its Keys, most Keys
  first, twenty to a page (`?view=members&page=N`). A person is a Regent
  account, with the Keys at every address it links counted together; Keys at
  an address no account links make a card of their own. Each card names the
  person (their chosen name over their short main address, else their ENS
  name, else their short main address), how many Keys they hold as small cards
  opening each Key, the Key they post as first in a slot of its own and then
  their lowest, their connected X, GitHub and Farcaster accounts, and whether
  they are active: a Key of theirs can vote now, as the Treasury counts
  presence.
  `club_claims` is the address the Regents Club's Keys wait at for their Pass
  holders, left out of the list; nil for a fleet with none.

  The page is read when it opens and again whenever the fleet's Keys change
  hands (`refresh/1`).

  Assigns: `id`, `fleet_id`, `club_claims`, `deck` (the fleet's `id`,
  `deck_hash` and `deck_size`), `params` (the page's address query) and
  `profile_open?`.
  """
  use RegentsWeb, :live_component

  alias Regents.Account.Accounts
  alias Regents.Account.Accounts.LinkedIdentity.Providers
  alias Regents.Account.Actors.System
  alias Regents.Account.PublicIdentity
  alias Regents.Keyfleet.Fleets.Rules
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.Metadata
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.PageRead
  alias RegentsWeb.NotFoundError

  @per_page 20
  @cards_shown 50
  @online_for 3600

  @doc "The Member List on show is read again: Keys changed hands in its fleet."
  def refresh(id), do: send_update(__MODULE__, id: id, refresh: true)

  @impl true
  def update(%{refresh: true}, socket), do: {:ok, read(socket)}

  def update(assigns, socket) do
    page = page!(assigns.params)
    socket = assign(socket, Map.put(assigns, :page, page))

    {:ok,
     if(changed?(socket, :page) or changed?(socket, :fleet_id),
       do: read(socket),
       else: socket
     )}
  end

  # The page the address names: the first when it names none.
  defp page!(%{"page" => page}) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page >= 1 and page <= 100_000 -> page
      _not_a_page -> raise NotFoundError
    end
  end

  defp page!(%{"page" => _not_text}), do: raise(NotFoundError)
  defp page!(_params), do: 1

  # A list that can't be read says so in its place; the rest of the fleet's
  # page stays.
  defp read(socket) do
    case PageRead.run("member list", fn -> holders(socket.assigns) end) do
      {:ok, {holders, next?}} ->
        assign(socket, holders: holders, next?: next?, now: DateTime.utc_now())

      {:error, _failure} ->
        assign(socket, holders: :unreadable, next?: false, now: DateTime.utc_now())
    end
  end

  defp holders(%{fleet_id: fleet_id, club_claims: club_claims, page: page, deck: deck}) do
    found =
      Keys.holders(fleet_id, List.wrap(club_claims), (page - 1) * @per_page, @per_page + 1)

    if found == [] and page > 1, do: raise(NotFoundError)

    {shown, more} = Enum.split(found, @per_page)
    {cards(fleet_id, deck, shown), more != []}
  end

  defp cards(_fleet_id, _deck, []), do: []

  defp cards(fleet_id, deck, holders) do
    wallets = Enum.flat_map(holders, & &1.wallets)
    held = Keys.lowest_held(fleet_id, wallets, @cards_shown)

    lowest =
      Map.new(
        holders,
        &{&1.wallets,
         &1.wallets |> Enum.flat_map(fn w -> Map.get(held, w, []) end) |> Enum.sort()}
      )

    faces = Keys.faces(fleet_id, for({_own, [first | _rest]} <- lowest, do: first))

    shown =
      Map.new(lowest, fn {own, [first | _rest] = keys} ->
        face = Map.fetch!(faces, first).face
        {own, Enum.take([face | List.delete(keys, face)], @cards_shown)}
      end)

    pictures = pictures(deck, shown |> Map.values() |> List.flatten())
    present = Keys.present_holders(fleet_id, wallets)
    idle = Keys.idle_holders(fleet_id, wallets)
    last_active = Keys.last_active(fleet_id, wallets)
    accounts = accounts(holders)
    connections = connections(Map.keys(accounts))

    for %{account_id: account_id, wallets: own, count: count} <- holders do
      account = accounts[account_id]
      {name, address, label} = who(account, own)
      [face | _rest] = shown = shown[own]

      %{
        id: card_id(account, own),
        count: count,
        name: name,
        address: address,
        label: label,
        connections: Map.get(connections, account_id, []),
        status: status(own, present, idle),
        last_active:
          own
          |> Enum.map(&last_active[&1])
          |> Enum.reject(&is_nil/1)
          |> Enum.max(DateTime, fn -> nil end),
        cards:
          for(
            token_id <- shown,
            do: %{token_id: token_id, image: pictures[token_id], face?: token_id == face}
          ),
        more: count - length(shown)
      }
    end
  end

  # The small cards are read a hundred Keys at a time.
  defp pictures(deck, token_ids),
    do:
      token_ids
      |> Enum.chunk_every(100)
      |> Enum.reduce(%{}, &Map.merge(&2, Metadata.small_cards(deck, &1)))

  # The accounts of the people on the page, by id.
  defp accounts(holders) do
    case for(%{account_id: id} <- holders, id, do: id) do
      [] ->
        %{}

      ids ->
        ids
        |> Accounts.accounts_by_ids!(actor: %System{}, load: [:display_name, :ens_name])
        |> Map.new(&{&1.id, &1})
    end
  end

  # The connections each account shows, by account id.
  defp connections([]), do: %{}

  defp connections(account_ids) do
    account_ids
    |> Accounts.list_linked_identities_for_accounts!(actor: %System{})
    |> Enum.group_by(& &1.human_account_id, &connection/1)
    |> Map.new(fn {account_id, links} -> {account_id, Enum.reject(links, &is_nil/1)} end)
  end

  # A person's card is known by their main address, an unlinked address's by
  # itself.
  defp card_id(%{wallet_address: wallet}, _own) when is_binary(wallet),
    do: String.downcase(wallet)

  defp card_id(_account, [wallet | _rest]), do: wallet

  # Returns the typed name, the main address and the ENS name.
  defp who(account, own) do
    {chosen, ens} = PublicIdentity.holder(account)
    {chosen, card_id(account, own), ens}
  end

  # A connection is shown only with the account name it links to.
  defp connection(identity) do
    with handle when is_binary(handle) <- Providers.handle(identity),
         url when is_binary(url) <- Providers.profile_url(identity.provider, identity.username) do
      %{label: Providers.label(identity.provider), handle: handle, url: url}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="member-list" aria-labelledby={"#{@id}-title"}>
      <h2 id={"#{@id}-title"}>Member List</h2>
      <p :if={@holders == :unreadable} id={"#{@id}-failed"}>
        Couldn’t read the members just now. <a href="">Try again</a>
      </p>
      <Regent.Primitives.empty_state
        :if={@holders == []}
        id={"#{@id}-none"}
        class="kf-empty"
        title="No members yet."
      >
        The first Key’s holder shows up here.
      </Regent.Primitives.empty_state>

      <ol :if={is_list(@holders)} id={"#{@id}-holders"} class="member-list__holders">
        <li
          :for={holder <- @holders}
          id={"#{@id}-holder-#{holder.id}"}
          class="member-card"
        >
          <p class="member-card__who">
            <strong :if={holder.name}>{holder.name}</strong>
            <Regent.Primitives.address
              id={"#{@id}-holder-#{holder.id}-address"}
              class={!holder.name && "member-card__identity"}
              address={holder.address}
              label={holder.label}
            />
            <span class="member-card__count">{Rules.keys(holder.count)}</span>
          </p>
          <p class="member-card__status" data-present={holder.status == :active && "true"}>
            {status_words(holder.status)}
            <.seen
              :if={holder.last_active}
              id={"#{@id}-holder-#{holder.id}-seen"}
              at={holder.last_active}
              now={@now}
            />
          </p>
          <p :if={holder.connections != []} class="member-card__connections">
            <span class="member-card__label">Connections</span>
            <a
              :for={link <- holder.connections}
              href={link.url}
              target="_blank"
              rel="noopener noreferrer nofollow"
            >
              {link.label} {link.handle}
            </a>
          </p>
          <ul class="fleet-entry__cards member-card__cards" aria-label="Keys held" tabindex="0">
            <li :for={card <- holder.cards} class={card.face? && "member-card__face"}>
              <span :if={card.face?} class="member-card__face-label">Posts as</span>
              <.link
                id={"#{@id}-card-#{card.token_id}"}
                class="fleet-entry__card"
                patch={KeyLinks.key_path(@fleet_id, card.token_id, @params)}
                replace={@profile_open?}
              >
                <img
                  :if={card.image}
                  src={card.image}
                  alt=""
                  width="48"
                  height="60"
                  loading="lazy"
                  decoding="async"
                />
                <span :if={!card.image} class="fleet-entry__blank"></span>
                Key {Rules.grouped(card.token_id)}
              </.link>
            </li>
            <li :if={holder.more > 0} class="fleet-entry__more">
              and {Rules.grouped(holder.more)} more
            </li>
          </ul>
        </li>
      </ol>

      <nav :if={@page > 1 or @next?} class="fleet-pages" aria-label="More members">
        <.link :if={@page > 1} id={"#{@id}-previous"} patch={page_path(@fleet_id, @page - 1)}>
          Previous
        </.link>
        <.link :if={@next?} id={"#{@id}-next"} patch={page_path(@fleet_id, @page + 1)}>
          Next
        </.link>
      </nav>
    </section>
    """
  end

  # Active when one of the holder's Keys has a vote now, Idle when none has and
  # one has lost it, and otherwise waiting: every Key is new and its
  # automatic start, 2 days after its sale, is still to come.
  defp status(wallets, present, idle) do
    cond do
      Enum.any?(wallets, &MapSet.member?(present, &1)) -> :active
      Enum.any?(wallets, &MapSet.member?(idle, &1)) -> :idle
      true -> :waiting
    end
  end

  defp status_words(:active), do: "Active"
  defp status_words(:idle), do: "Idle"
  defp status_words(:waiting), do: "Waiting to start"

  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :now, DateTime, required: true

  defp seen(assigns) do
    assigns = assign(assigns, :online?, DateTime.diff(assigns.now, assigns.at) < @online_for)

    ~H"""
    ·
    <%= if @online? do %>
      online now
    <% else %>
      last active
      <RegentsWeb.Keyfleet.Time.local
        id={@id}
        at={@at}
        as={:moment}
      />
    <% end %>
    """
  end

  defp page_path(fleet_id, 1), do: KeyLinks.members_path(fleet_id)
  defp page_path(fleet_id, page), do: KeyLinks.members_path(fleet_id, page)
end
