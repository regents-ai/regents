defmodule Regents.Keyfleet.Projects.Publish do
  @moduledoc """
  Makes something public as one of the fleet's Keys, and takes it back
  (`Regents.Keyfleet.Projects.Publication`). The actor acts as the Key the same way a
  workspace write does (`Regents.Keyfleet.Graph.Checks.KeyActor`), read again in
  the transaction that saves the step, an agent's pairing held until it
  commits.

  Posts are made public into an active project of the fleet, from one of the
  fleet's rooms (never a Key's thread), over a range of at most
  `Publication.most_posts/0` places that holds at least one post written as
  the Key for the wallet that owns it today, so a Key that changes hands
  never makes a former owner's posts public. A post is written for the owner
  when the owner's wallet wrote it, or a wallet the owner gave a shard of the
  Key: an agent writes as the Key with its own wallet.

  An item is made public into its own project, which is active, while it
  isn't archived, when the Key added it in the ownership it is in today,
  whoever wrote for the Key; each item once. A saved notebook page is made
  public, once, by the person or agent that made it (`Regents.Keyfleet.Notebooks.Makers`)
  acting as the Key, into the project whose notebook made it, which is
  active, once this site keeps its own copy of the page. A project's code at
  one commit is made public by the Key holding the project, which is active,
  once the code store has that commit; each commit once. Only the Key that
  made something public takes it back. A refusal says why in words
  (`Regents.Keyfleet.Projects.Errors.PublishError`).

  The room is read as the site reads it, whoever may read it: what is shown
  is what the Key chose to show, and only the posts written as that Key.
  """
  use Ash.Resource.Actions.Implementation

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.{Code, Keys, Notebooks, Rooms}
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Graph.Checks.KeyActor
  alias Regents.Keyfleet.Notebooks.Makers
  alias Regents.Keyfleet.Projects
  alias Regents.Keyfleet.Projects.Errors.{PublishError, UnknownProjectError}
  alias Regents.Keyfleet.Projects.Publication

  @system %Regents.Account.Actors.System{}

  @impl true
  def run(input, opts, %{actor: actor}) do
    %{fleet_id: fleet_id, as_key: key} = input.arguments
    within = Application.fetch_env!(:regents, :keyfleet_graph)[:check_timeout]

    with {:ok, _command} <- KeyActor.command(actor, fleet_id, key, nil, within),
         {:ok, change} <- step(Keyword.fetch!(opts, :step), fleet_id, key, input.arguments, actor) do
      Ash.transact(Publication, fn -> held_save(change, actor, fleet_id, key, within) end)
    end
  end

  # What a step makes is saved with the actor's standing read again in its
  # transaction, an agent's pairing held until it commits.
  defp held_save(change, actor, fleet_id, key, within) do
    with {:ok, _command} <- KeyActor.held_command(actor, fleet_id, key, nil, within),
         {:ok, saved} <- save(change),
         do: saved
  end

  defp save(%Ash.Changeset{action_type: :create} = change), do: Ash.create(change)

  defp save(%Ash.Changeset{action_type: :destroy} = change),
    do: Ash.destroy(change, return_destroyed?: true)

  defp record(attributes),
    do: {:ok, Ash.Changeset.for_create(Publication, :record, attributes, actor: @system)}

  defp step(:posts, fleet_id, key, %{project: project, room: room} = arguments, _actor) do
    %{from_seq: from, to_seq: to} = arguments

    with :ok <- active(fleet_id, project),
         :ok <- range(from, to),
         :ok <- room(fleet_id, room),
         {:ok, %{owner_wallet: owner}} <- held(fleet_id, key),
         :ok <- written(fleet_id, room, from, to, key, owner) do
      record(%{
        fleet_id: fleet_id,
        project: project,
        key: key,
        author_wallet: owner,
        kind: :posts,
        room: room,
        from_seq: from,
        to_seq: to
      })
    end
  end

  defp step(:item, fleet_id, key, %{item: id}, _actor) do
    with {:ok, object} <- item(fleet_id, id),
         :ok <- active(fleet_id, object.project),
         :ok <- once(Projects.item_publication(fleet_id, id, actor: @system), "item"),
         {:ok, %{owner_wallet: owner, ownership_epoch: epoch}} <- held(fleet_id, key),
         :ok <- added(object, key, epoch) do
      record(%{
        fleet_id: fleet_id,
        project: object.project,
        key: key,
        author_wallet: owner,
        kind: :item,
        item: id
      })
    end
  end

  defp step(:page, fleet_id, key, %{page: address}, actor) do
    with {:ok, path, {notebook_id, source_id, saved_at}} <- page(fleet_id, address),
         :ok <- kept(fleet_id, notebook_id, source_id, saved_at),
         {:ok, subject} <- subject(actor),
         {:ok, project} <- made(fleet_id, subject, notebook_id, source_id),
         :ok <- active(fleet_id, project),
         :ok <- once(Projects.page_publication(fleet_id, path, actor: @system), "page"),
         {:ok, %{owner_wallet: owner}} <- held(fleet_id, key) do
      record(%{
        fleet_id: fleet_id,
        project: project,
        key: key,
        author_wallet: owner,
        kind: :page,
        page: path
      })
    end
  end

  defp step(:commit, fleet_id, key, %{project: project, commit_hash: hash}, _actor) do
    with :ok <- active(fleet_id, project),
         :ok <- holds(fleet_id, project, key),
         :ok <- committed(fleet_id, project, hash),
         :ok <-
           once(Projects.commit_publication(fleet_id, project, hash, actor: @system), "commit"),
         {:ok, %{owner_wallet: owner}} <- held(fleet_id, key) do
      record(%{
        fleet_id: fleet_id,
        project: project,
        key: key,
        author_wallet: owner,
        kind: :commit,
        commit_hash: hash
      })
    end
  end

  defp step(:withdraw, fleet_id, key, %{id: id}, _actor) do
    case Ash.get(Publication, id, actor: @system, not_found_error?: false) do
      {:ok, %{fleet_id: ^fleet_id, key: ^key} = publication} ->
        {:ok, Ash.Changeset.for_destroy(publication, :remove, %{}, actor: @system)}

      {:ok, %{fleet_id: ^fleet_id} = publication} ->
        refuse(
          :not_yours,
          "Key #{publication.key} made this public. Only that Key takes it back."
        )

      {:ok, _other} ->
        refuse(:unknown, "This fleet has nothing public by that id.")

      {:error, error} ->
        {:error, error}
    end
  end

  defp active(fleet_id, name) do
    case Projects.project(fleet_id, name, actor: @system) do
      {:ok, %{state: :active}} ->
        :ok

      {:ok, nil} ->
        {:error, UnknownProjectError.exception(fleet_id: fleet_id, project: name)}

      {:ok, project} ->
        refuse(
          :project_archived,
          "#{project.title} is archived. Make posts public in an active project."
        )

      {:error, error} ->
        {:error, error}
    end
  end

  defp range(from, to) when to < from,
    do: refuse(:range, "The last post comes after the first.")

  defp range(from, to) do
    if to - from < Publication.most_posts(),
      do: :ok,
      else: refuse(:range, "Make at most #{Publication.most_posts()} posts public at once.")
  end

  defp room(fleet_id, slug) do
    # The record shows a room's posts to anyone, so the room is found as the
    # site finds it, not as the reader may see it.
    case Rooms.get_room(fleet_id, slug, authorize?: false) do
      {:ok, %{}} -> :ok
      {:ok, nil} -> refuse(:room_unknown, "This fleet has no room #{slug}.")
      {:error, error} -> {:error, error}
    end
  end

  defp item(fleet_id, id) do
    case Graph.read_objects(fleet_id, [id], actor: @system) do
      {:ok, [%{sys: %{"archived" => true}}]} ->
        refuse(:item_archived, "This item is archived. Only an item in use goes public.")

      {:ok, [object]} ->
        {:ok, object}

      {:ok, []} ->
        refuse(:item_unknown, "This workspace has no item #{id}.")

      {:error, error} ->
        {:error, error}
    end
  end

  defp holds(fleet_id, name, key) do
    case Projects.project(fleet_id, name, actor: @system) do
      {:ok, %{key: ^key}} ->
        :ok

      {:ok, project} ->
        refuse(:not_holder, "Only the Key holding #{project.title} makes its code public.")

      {:error, error} ->
        {:error, error}
    end
  end

  # The code store has the commit in the project's repository.
  defp committed(fleet_id, project, hash) do
    with true <- Code.full_hash?(hash),
         {:ok, repository} when is_binary(repository) <- Code.repository(fleet_id, project),
         {:ok, [_ | _]} <- Code.folder(repository, "", hash) do
      :ok
    else
      {:error, {:code_store_status, status}} when status in [400, 404] -> unknown_commit(project)
      {:error, _unreadable} -> refuse(:code_unavailable, "The code can't be read right now.")
      _none -> unknown_commit(project)
    end
  end

  defp unknown_commit(project),
    do: refuse(:commit_unknown, "The code of #{project} has no commit by that full hash.")

  defp once({:ok, nil}, _thing), do: :ok

  defp once({:ok, _public}, thing),
    do: refuse(:already_public, "This #{thing} is already public.")

  defp once({:error, error}, _thing), do: {:error, error}

  # A saved page by its address on the fleet's notebook host, or its path.
  defp page(fleet_id, address) do
    path = String.replace_prefix(address, Notebooks.url(fleet_id, ""), "")

    case Notebooks.result(path) do
      {:ok, parts} ->
        {:ok, path, parts}

      :error ->
        refuse(
          :page_unknown,
          "Name a saved notebook page by its address, as the notebook gives it."
        )
    end
  end

  # Only a page this site keeps its own copy of opens for anyone.
  defp kept(fleet_id, notebook_id, source_id, saved_at) do
    case Notebooks.saved_output(fleet_id, notebook_id, source_id, saved_at, actor: @system) do
      {:ok, nil} -> refuse(:page_unknown, "This fleet's notebooks have no saved page there.")
      {:ok, _kept} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  # How the fleet's notebooks know whoever acts.
  defp subject(%Human{} = actor), do: {:ok, Notebooks.subject(actor)}

  defp subject(actor) do
    case Notebooks.agent(actor) do
      {:ok, nil} ->
        refuse(:not_made, "Only the person or agent that made a saved page makes it public.")

      {:ok, subject} ->
        {:ok, subject}

      {:error, error} ->
        {:error, error}
    end
  end

  # The project whose notebook made the page, when `subject` made it.
  defp made(fleet_id, subject, notebook_id, source_id) do
    case Makers.result_project(fleet_id, subject, notebook_id, source_id) do
      {:ok, project} ->
        {:ok, project}

      {:error, :not_maker} ->
        refuse(:not_made, "Only the person or agent that made a saved page makes it public.")

      {:error, :not_found} ->
        refuse(:page_unknown, "This fleet's notebooks have no saved page there.")

      {:error, :unavailable} ->
        refuse(:page_unavailable, "The notebooks can't say who made this page right now.")
    end
  end

  # The Key added the item in the ownership it is in today: every write as a
  # Key carries the ownership it was made in.
  defp added(%{sys: %{"created_by" => %{"key" => %{"token_id" => key}} = by}}, key, epoch) do
    if by["ownership_epoch"] == epoch,
      do: :ok,
      else: refuse(:not_added, "Key #{key} added this item for an earlier owner.")
  end

  defp added(_object, key, _epoch),
    do:
      refuse(
        :not_added,
        "Key #{key} didn’t add this item. A Key makes public only what it added."
      )

  # The Key as it is held today: its owner's wallet and its ownership.
  defp held(fleet_id, key) do
    case Keys.current_key(fleet_id, key, authorize?: false) do
      {:ok, %{} = held} -> {:ok, held}
      {:ok, nil} -> refuse(:key_unknown, "This fleet has no Key #{key}.")
      {:error, error} -> {:error, error}
    end
  end

  defp written(fleet_id, room, from, to, key, owner) do
    if Enum.any?(posts(fleet_id, room, from, to, key, owner)),
      do: :ok,
      else: refuse(:none_written, "Key #{key} wrote no post there from #{from} to #{to}.")
  end

  @doc """
  The posts written as `key` for the wallet `owner` in the fleet's room
  `room` from place `from` to `to`, oldest first, each with its author, read
  whoever may read the room. The owner's wallet wrote them, or a wallet the
  owner gave a shard of the Key.
  """
  def posts(fleet_id, room, from, to, key, owner) do
    writers = writers(fleet_id, key, owner)

    fleet_id
    |> Rooms.read_messages!(
      room,
      %{after_seq: from - 1, limit: to - from + 1},
      # The Key chose to show these posts, so they are read whoever reads them.
      authorize?: false,
      load: [:reply_to_seq]
    )
    |> Enum.filter(
      &(&1.kind == :post and &1.as_key == key and &1.author_wallet in writers and &1.seq <= to)
    )
  end

  # The wallets that write as `key` for the wallet `owner`: the owner's own,
  # and each wallet the owner gave a shard of the Key while it held it.
  defp writers(fleet_id, key, owner) do
    fleet_id
    # Which wallets the owner gave a shard decides whose posts are the Key's,
    # whoever is reading.
    |> Keys.shards_issued_by_owner!(key, owner, authorize?: false)
    |> MapSet.new(& &1.wallet)
    |> MapSet.put(owner)
  end

  defp refuse(code, words), do: {:error, PublishError.exception(code: code, words: words)}
end
