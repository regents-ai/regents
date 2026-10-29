defmodule RegentsWeb.ShellLive.Names do
  @moduledoc """
  The Names page: the Regent names the signed-in wallets have claimed, and
  claiming another with a free claim. Every read here is the account's own, made
  with the wallets its sign-in verified, so nothing the browser sends can widen it.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 3, stream: 4]

  alias Regents.Actors.Human
  alias Regents.Names
  alias RegentsWeb.EventInput
  alias RegentsWeb.ShellLive.Identity

  @page_size 50
  @blank_claim_name %{value: "", problems: [], availability: nil}
  # Far longer than any name a person claims; the name's own rules say what is too long.
  @claim_name_limit 255

  @events ~w(load_more_names check_claim_name claim_name)

  def handles?(event), do: event in @events

  def init(socket), do: socket |> stream(:names, []) |> cleared()

  def route(socket, %{route_id: :names}), do: socket |> load_names() |> load_claims()
  def route(socket, _route_spec), do: cleared(socket)

  defp cleared(socket),
    do: assign(socket, names: nil, name_claims: nil, claim_name: @blank_claim_name)

  def handle_event(_event, _params, %{assigns: %{route_spec: %{route_id: route_id}}} = socket)
      when route_id != :names,
      do: socket

  def handle_event("load_more_names", _params, socket), do: load_more_names(socket)

  def handle_event("check_claim_name", %{"name" => name}, socket)
      when is_binary(name) and byte_size(name) <= @claim_name_limit,
      do: assign(socket, claim_name: check_claim_name(socket, name))

  def handle_event("claim_name", %{"name" => name}, socket)
      when is_binary(name) and byte_size(name) <= @claim_name_limit,
      do: claim_name(socket, name)

  def handle_event(_event, _params, socket),
    do: Phoenix.LiveView.put_flash(socket, :error, EventInput.unreadable())

  # The list is oldest first and grows a page at a time as the reader reaches
  # its end. The rows go to the browser and only the place to continue from is
  # kept here; a page that cannot be read leaves the rows already shown in place.
  defp load_names(socket) do
    case Identity.human_actor(socket) do
      %Human{wallet_addresses: []} ->
        first_page(socket, %{results: [], more?: false})

      %Human{} = actor ->
        case Names.list_my_claims(actor: actor, page: [limit: @page_size]) do
          {:ok, page} -> first_page(socket, page)
          {:error, _error} -> assign(socket, names: :unavailable)
        end

      nil ->
        assign(socket, names: nil)
    end
  end

  defp first_page(socket, page) do
    socket
    |> stream(:names, page.results, reset: true)
    |> assign(
      names: %{
        empty?: page.results == [],
        more?: page.more?,
        cursor: cursor(page.results),
        stalled?: false
      }
    )
  end

  defp load_more_names(%{assigns: %{names: %{more?: true} = names}} = socket) do
    case Names.list_my_claims(
           actor: Identity.human_actor(socket),
           page: [limit: @page_size, after: names.cursor]
         ) do
      {:ok, page} ->
        socket
        |> stream(:names, page.results)
        |> assign(names: %{names | more?: page.more?, cursor: cursor(page.results)})

      {:error, _error} ->
        assign(socket, names: %{names | more?: false, stalled?: true})
    end
  end

  defp load_more_names(socket), do: socket

  defp cursor([]), do: nil
  defp cursor(claims), do: List.last(claims).__metadata__.keyset

  # The claims the signed-in wallets may still make, read the same way as the
  # names they hold. A read that fails is shown as unanswered, never as none.
  defp load_claims(socket) do
    claims =
      case Identity.human_actor(socket) do
        %Human{wallet_addresses: []} -> %{free: 0, paid: 0}
        %Human{} = actor -> claims_available(actor)
        nil -> nil
      end

    assign(socket, name_claims: claims, claim_name: @blank_claim_name)
  end

  defp claims_available(actor) do
    case Names.claims_available(actor: actor) do
      {:ok, claims} -> claims
      {:error, _error} -> :unavailable
    end
  end

  # A name is judged as it is typed: the rules first, then whether a recorded
  # claim already holds it. The claim itself is not made here.
  defp check_claim_name(_socket, ""), do: @blank_claim_name

  defp check_claim_name(socket, name) do
    case Names.label_problems(name) do
      [] -> %{value: name, problems: [], availability: availability(socket, name)}
      problems -> %{value: name, problems: problems, availability: nil}
    end
  end

  # The claim is made by the account's own sign-in and judged again where it
  # is recorded, whatever the page showed. Afterwards everything the claim
  # could have changed is read again, so a refusal is explained by what is
  # true now: the name taken, or no free claim left.
  defp claim_name(socket, name) do
    with %Human{} = actor <- Identity.human_actor(socket),
         {:ok, claim} <- Names.claim_free_name(name, actor: actor) do
      socket
      |> load_names()
      |> load_claims()
      |> assign(claim_name: %{@blank_claim_name | availability: {:claimed_now, claim.ens_fqdn}})
    else
      nil ->
        socket

      {:error, _error} ->
        socket
        |> load_claims()
        |> then(&assign(&1, claim_name: refused_claim_name(&1, name)))
    end
  end

  defp refused_claim_name(socket, name) do
    case {check_claim_name(socket, name), socket.assigns.name_claims} do
      {%{availability: :available} = claim_name, %{free: free}} when free > 0 ->
        %{claim_name | availability: :not_claimed}

      {claim_name, _claims} ->
        claim_name
    end
  end

  defp availability(socket, name) do
    case Names.label_claimed?(name, actor: Identity.human_actor(socket)) do
      {:ok, true} -> :claimed
      {:ok, false} -> :available
      {:error, _error} -> :unavailable
    end
  end
end
