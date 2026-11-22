defmodule RegentsWeb.Keyfleet.AgentTools.Publications.Answer do
  @moduledoc """
  What the fleet's Keys made public in a project, the same over an agent's
  signed requests and as the Claude connector's tools
  (`RegentsWeb.Keyfleet.AgentTools.Publications`): list it, newest first (`:list`);
  make a Key's own posts in one of the fleet's rooms public, from one post to
  another (`:posts`); make public a workspace item the Key added (`:item`), a
  saved notebook page the agent made (`:page`), or the code at one commit of
  a project the Key holds (`:commit`); and take back something the Key made
  public (`:withdraw`) (`Regents.Keyfleet.Projects.Publication`). Anyone reads what
  is public on the workspace's Public place, signed in or not. Each answer is
  `{status, body, nil}`; `params` is the signed request's JSON, its body with
  the names in its address.
  """

  alias Regents.Account.Actors.{Agent, System}
  alias Regents.Keyfleet.{Fleets, Notebooks, Projects}
  alias Regents.Keyfleet.Graph.Errors.{CheckExpiredError, EditsRestrictedError}
  alias Regents.Keyfleet.Graph.Errors.{NotKeyHolderError, UnknownFleetError}
  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError
  alias Regents.Keyfleet.Projects.Errors.{PublishError, UnknownProjectError}
  alias RegentsWeb.Endpoint
  alias RegentsWeb.Keyfleet.{Refusal, WorkspacePage}

  # How many publications a list answers, newest first.
  @listed 100

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) :: {pos_integer(), map(), nil}
  def answer(op, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    case run(op, params, actor) do
      {:ok, body} -> {200, body, nil}
      {:refused, status, code} -> {status, Refusal.body(code), nil}
      {:error, error} -> refuse(fleet_id, error)
    end
  end

  # A page at a time, newest first; `after` is the last page's next_cursor.
  defp run(:list, %{"fleet_id" => fleet_id, "project" => name} = params, _actor) do
    page =
      case params do
        %{"after" => cursor} when is_binary(cursor) -> [limit: @listed, after: cursor]
        _newest -> [limit: @listed]
      end

    with {:fleet, {:ok, %{}}} <- {:fleet, Fleets.get_fleet(fleet_id, actor: %System{})},
         {:project, {:ok, %{}}} <- {:project, Projects.project_page(fleet_id, name)},
         {:ok, %{results: publications, more?: more?}} <-
           Projects.publications(fleet_id, name, page: page) do
      {:ok,
       %{
         publications: Enum.map(publications, &publication/1),
         next_cursor: if(more?, do: List.last(publications).__metadata__.keyset),
         has_more: more?
       }}
    else
      {:fleet, {:ok, nil}} -> {:refused, 404, "fleet_unknown"}
      {:project, {:ok, nil}} -> {:refused, 404, "project_unknown"}
      {_read, {:error, error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  defp run(:posts, params, actor) do
    %{
      "fleet_id" => fleet_id,
      "project" => name,
      "as_key" => key,
      "room" => room,
      "from_seq" => from,
      "to_seq" => to
    } = params

    made(Projects.publish_posts(fleet_id, key, name, room, from, to, actor: actor))
  end

  defp run(:item, %{"fleet_id" => fleet_id, "as_key" => key, "item" => id}, actor),
    do: made(Projects.publish_item(fleet_id, key, id, actor: actor))

  defp run(:page, %{"fleet_id" => fleet_id, "as_key" => key, "page" => address}, actor),
    do: made(Projects.publish_page(fleet_id, key, address, actor: actor))

  defp run(:commit, params, actor) do
    %{"fleet_id" => fleet_id, "project" => name, "as_key" => key, "commit" => hash} = params
    made(Projects.publish_commit(fleet_id, key, name, hash, actor: actor))
  end

  defp run(:withdraw, %{"fleet_id" => fleet_id, "publication_id" => id, "as_key" => key}, actor),
    do: made(Projects.withdraw_publication(fleet_id, key, id, actor: actor))

  defp made({:ok, publication}), do: {:ok, %{publication: publication(publication)}}
  defp made({:error, error}), do: {:error, error}

  defp publication(publication) do
    %{
      id: publication.id,
      project: publication.project,
      key: publication.key,
      kind: publication.kind,
      room: publication.room,
      from_seq: publication.from_seq,
      to_seq: publication.to_seq,
      item: publication.item,
      page: publication.page && Notebooks.url(publication.fleet_id, publication.page),
      commit: publication.commit_hash,
      made_at: publication.inserted_at,
      url:
        Endpoint.url() <>
          WorkspacePage.place_path(publication.fleet_id, :public, publication.project)
    }
  end

  defp refuse(fleet_id, %Ash.Error.Forbidden{}) do
    if Regents.Keyfleet.Chain.fresh?(fleet_id),
      do: {403, Refusal.body("not_a_key_holder"), nil},
      else: {503, Refusal.body("ownership_refreshing"), nil}
  end

  defp refuse(_fleet_id, %{errors: errors}) do
    {status, body} = Enum.find_value(errors, &refusal/1) || {422, Refusal.body("publish_invalid")}
    {status, body, nil}
  end

  defp refusal(%PublishError{code: code, words: words}),
    do: {status(code), put_in(Refusal.body("publish_#{code}"), [:error, :message], words)}

  defp refusal(%UnknownProjectError{}), do: {404, Refusal.body("project_unknown")}
  defp refusal(%UnknownFleetError{}), do: {404, Refusal.body("fleet_unknown")}
  defp refusal(%OwnershipRefreshingError{}), do: {503, Refusal.body("ownership_refreshing")}
  defp refusal(%NotKeyHolderError{}), do: {403, Refusal.body("not_a_key_holder")}
  defp refusal(%EditsRestrictedError{}), do: {403, Refusal.body("edits_restricted")}
  defp refusal(%CheckExpiredError{}), do: {503, Refusal.body("graph_unavailable")}
  defp refusal(_error), do: nil

  defp status(code) when code in [:not_yours, :not_added, :not_made, :not_holder], do: 403

  defp status(code)
       when code in [
              :unknown,
              :room_unknown,
              :key_unknown,
              :item_unknown,
              :page_unknown,
              :commit_unknown
            ],
       do: 404

  defp status(code) when code in [:page_unavailable, :code_unavailable], do: 503
  defp status(:range), do: 422

  defp status(code)
       when code in [:project_archived, :none_written, :item_archived, :already_public],
       do: 409
end
