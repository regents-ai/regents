defmodule Regents.Keyfleet.Notebooks.Roster do
  @moduledoc """
  Brings one fleet's notebook hub in step with who holds the fleet's keys now.

  A shared project the fleet no longer shares is deleted first, its space
  with it (`Regents.Keyfleet.Projects.unshare!/1`). Any of the fleet's projects still
  without a space in the hub gets the job that makes one
  (`Regents.Keyfleet.Notebooks.Space`), which runs this again once the space is made.
  Its first request makes this site's provisioner the hub's first user.

  Then everyone who holds one of the fleet's keys, an agent with an active
  shard of one, or an agent paired with a person who holds one, is an editor
  of every space the fleet's projects have; anyone else this site added
  loses their place in each, their open notebook connections close, and they
  are suspended in that hub, so nothing they hold there still lets them in.
  Someone who holds a key again is let back in. Once the hub is in step,
  every Key of a fleet with a scratchpad gets its notebook there
  (`Regents.Keyfleet.Notebooks.Scratchpads`).

  It runs whenever a key changes hands or a shard is issued or ended, and
  again when an issued shard runs out (`Regents.Keyfleet.Notebooks.Changes.UpdateRoster`),
  and for every fleet every ten minutes (`Regents.Keyfleet.Notebooks.Reconcile`). Every step is safe to repeat, and a
  run that fails part way is run again from the start. While the fleet's key
  ownership is still being read, a run ends without changing the hub, and the
  next ten-minute run takes it up.

  Runs go one at a time (the `keyfleet_notebook_hubs` queue runs one job). One run per
  fleet waits to start at a time; a change made while one runs queues the
  next, so the last run always reads the latest owners. A run booked for when
  a shard runs out doesn't count as waiting, so it never holds back a run
  wanted now.
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_hubs,
    max_attempts: 20,
    unique: [keys: [:fleet_id], period: :infinity, states: [:available, :retryable]]

  alias Regents.Account.Actors.{Agent, Human, System}
  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError
  alias Regents.Keyfleet.{Notebooks, Projects}
  alias Regents.Keyfleet.Notebooks.{HubClient, Scratchpads, Space}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fleet_id" => fleet_id}}) do
    with true <- Notebooks.hub?(fleet_id) || {:cancel, :no_hub},
         {:ok, spaces} <- spaces(fleet_id),
         {:ok, holders} <- holders(fleet_id),
         {:ok, members} <- members(fleet_id, spaces),
         {:ok, users} <- HubClient.users(fleet_id),
         :ok <- sync(fleet_id, holders, members, users) do
      if "scratchpad" in Projects.Project.shared_names(fleet_id),
        do: Oban.insert!(Scratchpads.new(%{fleet_id: fleet_id}))

      :ok
    else
      {:error, %OwnershipRefreshingError{}} -> {:cancel, :ownership_refreshing}
      other -> other
    end
  end

  # The spaces made so far, once a shared project the fleet no longer shares
  # is deleted; each project without one gets the job that makes it.
  defp spaces(fleet_id) do
    :ok = Projects.unshare!(fleet_id)

    with {:ok, projects} <- Projects.projects(fleet_id, actor: %System{}) do
      for %{hub_project_id: nil} = project <- projects,
          do: Oban.insert!(Space.new(%{fleet_id: fleet_id, project: project.name}))

      {:ok, for(%{hub_project_id: space} <- projects, space, do: space)}
    end
  end

  # Each space's members this site added, by subject, with how the hub names each.
  defp members(fleet_id, spaces) do
    Enum.reduce_while(spaces, {:ok, %{}}, fn space, {:ok, all} ->
      case HubClient.members(fleet_id, space) do
        {:ok, members} ->
          {:cont, {:ok, Map.put(all, space, ours(members))}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp ours(members),
    do: for(member <- members, subject = member_subject(member), into: %{}, do: {subject, member})

  # The subjects who hold one of the fleet's keys, or an active shard of one,
  # now, and the agents paired with a person who holds one. An agent's pairing
  # is read as each request reads it, from the person the profile last named;
  # the gateway's own check on every request is still what lets it in.
  defp holders(fleet_id) do
    wallets =
      Regents.Keyfleet.Keys.KeyAttachment
      |> Ash.Query.for_read(:current_in_fleet, %{fleet_id: fleet_id})
      |> Ash.stream!(actor: %System{}, batch_size: 100)
      |> Enum.map(& &1.owner_wallet)
      |> Enum.uniq()

    people =
      wallets
      |> Enum.chunk_every(100)
      |> Enum.flat_map(&Regents.Account.Accounts.accounts_holding_wallets!(&1, actor: %System{}))
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&{Notebooks.subject(Human.for_account(&1)), Human.for_account(&1)})

    agents =
      [fleet_id]
      |> Regents.Keyfleet.Agents.agents_here_in!(actor: %System{})
      |> Enum.flat_map(fn profile ->
        case Regents.Keyfleet.Agents.with_pairing(%Agent{
               wallet_address: profile.wallet_address,
               chain_id: 8453,
               verification_method: :eoa_recovery,
               audience: "regents",
               human_id: profile.human_id
             }) do
          {:ok, actor} -> [{Notebooks.agent_subject(profile.id), actor}]
          {:error, :not_paired} -> []
          {:error, error} -> raise "notebook pairing check failed: #{inspect(error.__struct__)}"
        end
      end)

    Enum.reduce_while(people ++ agents, {:ok, MapSet.new()}, fn {subject, actor},
                                                                {:ok, holders} ->
      case Notebooks.member?(actor, fleet_id) do
        {:ok, true} -> {:cont, {:ok, MapSet.put(holders, subject)}}
        {:ok, false} -> {:cont, {:ok, holders}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp sync(fleet_id, holders, members, users) do
    managed = Enum.filter(users, &Notebooks.managed_subject?(&1["id"]))
    leaving = for %{"id" => id} <- managed, id not in holders, do: id

    leaving =
      Enum.uniq(
        leaving ++
          for(
            {_space, ours} <- members,
            subject <- Map.keys(ours),
            subject not in holders,
            do: subject
          )
      )

    Enum.each(leaving, &Notebooks.end_access(fleet_id, &1))

    steps =
      Enum.concat([
        for(
          {space, ours} <- members,
          subject <- leaving,
          Map.has_key?(ours, subject),
          do: fn -> HubClient.remove_member(fleet_id, space, member_ref(ours[subject])) end
        ),
        for(
          %{"id" => id, "suspended_at" => nil} <- managed,
          id in leaving,
          do: fn -> HubClient.suspend(fleet_id, id) end
        ),
        for(
          %{"id" => id, "suspended_at" => at} <- managed,
          at != nil,
          id in holders,
          do: fn -> HubClient.reactivate(fleet_id, id) end
        ),
        for(
          {space, ours} <- members,
          subject <- holders,
          not Map.has_key?(ours, subject),
          do: fn -> HubClient.add_editor(fleet_id, space, subject) end
        )
      ])

    Enum.reduce_while(steps, :ok, fn step, :ok ->
      case step.() do
        {:ok, _answer} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp member_subject(%{"user_id" => id}), do: if(Notebooks.managed_subject?(id), do: id)
  defp member_subject(%{"email" => email}), do: Notebooks.subject_of_email(email)

  defp member_ref(%{"user_id" => id}), do: id
  defp member_ref(%{"email" => email}), do: email
end
