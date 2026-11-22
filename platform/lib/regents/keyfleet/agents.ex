defmodule Regents.Keyfleet.Agents do
  @moduledoc """
  Wallet-owned agent profiles, independent of NFT authority, and when each
  agent checks in with each fleet.
  """
  use Ash.Domain

  import Ash.Expr, only: [expr: 1]
  require Ash.Query
  require Logger

  resources do
    resource Regents.Keyfleet.Agents.AgentProfile do
      define :ensure_profile, action: :ensure_profile
      define :get_my_profile, action: :get_my_profile, not_found_error?: false
      define :edit_my_profile, action: :edit_my_profile
      define :set_avatar, action: :set_avatar, args: [:avatar_key]
      define :remove_avatar, action: :remove_avatar
      define :agents_here, action: :here_in_fleet, args: [:fleet_id]
      define :agents_by_wallets, action: :by_wallets, args: [:wallets]
      define :listings, action: :listings, args: [:ids]
      define :agents_of_people, action: :of_people, args: [:human_ids]
      define :agents_here_in, action: :here_in_fleets, args: [:fleet_ids]
    end

    resource Regents.Keyfleet.Agents.CheckIn do
      define :get_check_in,
        action: :read,
        get_by: [:agent_profile_id, :fleet_id],
        not_found_error?: false

      define :check_ins_in_fleet, action: :in_fleet, args: [:fleet_id, :agent_profile_ids]
      define :blocked_check_ins, action: :blocked, args: [:wallets]
    end

    resource Regents.Keyfleet.Agents.Checkpoint do
      define :checkpoint, action: :mine, args: [:fleet_id], not_found_error?: false
      define :start_checkpoint, action: :start, args: [:fleet_id, :state]
    end
  end

  alias Ash.Error.Changes.StaleRecord

  alias Regents.Keyfleet.Agents.{
    Avatar,
    AvatarBucket,
    CheckIn,
    CheckInStatus,
    Checkpoint,
    DeleteAvatar
  }

  @doc """
  Saves `state` as the agent's checkpoint in `fleet_id`, from the revision
  it read, `expected_revision` (0 when it has none): `{:ok, checkpoint}` at
  the next revision, or `{:stale, current}` with the checkpoint as it is now
  (nil for none) when that wasn't the revision kept, and nothing is saved.
  An agent unpaired while the save was on its way is refused with that
  error (`unpaired?/1`).
  """
  def save_checkpoint(actor, fleet_id, 0, state) do
    case start_checkpoint(fleet_id, state, actor: actor) do
      {:ok, checkpoint} ->
        {:ok, checkpoint}

      {:error, error} = refused ->
        if unpaired?(error), do: refused, else: stale_or(refused, actor, fleet_id)
    end
  end

  def save_checkpoint(actor, fleet_id, expected_revision, state) do
    case checkpoint(fleet_id, actor: actor) do
      {:ok, %Checkpoint{revision: ^expected_revision} = kept} ->
        with {:error, error} <- Ash.update(kept, %{state: state}, action: :save, actor: actor),
             do: saved_since(error, actor, fleet_id)

      {:ok, current} ->
        {:stale, current}

      {:error, error} ->
        {:error, error}
    end
  end

  # Another save made the next revision between this one's read and its write.
  defp saved_since(error, actor, fleet_id) do
    if Enum.any?(List.wrap(Map.get(error, :errors, error)), &is_struct(&1, StaleRecord)),
      do: stale_or(nil, actor, fleet_id),
      else: {:error, error}
  end

  # A first save that found one already kept, or a later one from another
  # revision, answers the checkpoint as it is now; a first save refused with
  # none kept answers that refusal.
  defp stale_or(refused, actor, fleet_id) do
    case checkpoint(fleet_id, actor: actor) do
      {:ok, nil} when refused != nil -> refused
      {:ok, current} -> {:stale, current}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The names agents gave themselves, as `%{wallet => name}`, for the agents
  among `wallets` that have a profile, read a hundred wallets at a time.
  """
  def names_by_wallet(wallets) do
    case wallets |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] ->
        %{}

      wallets ->
        wallets
        |> Enum.chunk_every(100)
        |> Enum.flat_map(&agents_by_wallets!/1)
        |> Map.new(&{&1.wallet_address, &1.name})
    end
  end

  @doc """
  Each agent's check-in light, as `%{wallet => %{light: "on" | "late" | "off" |
  nil, light_label: words | nil}}`, for every wallet in `wallets`: the best
  light of its check-ins with any fleet (on, then late, then off) and that
  light's words (`CheckInStatus`). An agent that never came to Keyfleet has no
  light, both nil.
  """
  def check_in_lights(wallets, now) do
    seen =
      wallets
      |> Enum.chunk_every(100)
      |> Enum.flat_map(&agents_by_wallets!(&1, load: [:check_ins]))
      |> Map.new(&{&1.wallet_address, best_light(&1.check_ins, now)})

    Map.new(wallets, &{&1, Map.get(seen, &1, %{light: nil, light_label: nil})})
  end

  @light_rank %{on: 0, late: 1, off: 2}

  defp best_light(check_ins, now) do
    {light, {_status, label}} =
      check_ins
      |> Enum.map(&{CheckInStatus.light(&1, now), CheckInStatus.derive(&1, now)})
      |> Enum.min_by(
        fn {light, _status} -> @light_rank[light] end,
        fn -> {:off, CheckInStatus.derive(nil, now)} end
      )

    %{light: Atom.to_string(light), light_label: label}
  end

  @doc """
  Whether the signed-in person has an agent paired to their Regent account,
  from their Agents page here or on any Regent site. A reading that fails
  counts as none.
  """
  def has_paired_agent?(%Regents.Account.Actors.Human{} = actor), do: my_agents(actor) != []

  @doc """
  The agents paired to the signed-in person's Regent account, from their Agents
  page here or on any Regent site. A reading that fails counts as none.
  """
  def my_agents(%Regents.Account.Actors.Human{human_account_id: id} = actor) do
    with {:ok, account} <- Regents.Account.Accounts.get_human_account(id, actor: actor),
         {:ok, agents} <-
           RegentAgents.list_my_agents(
             actor: %RegentAgents.Person{privy_user_id: account.privy_user_id}
           ) do
      agents
    else
      _none -> []
    end
  end

  @doc "Each of `wallets`' check-ins with the fleet, as `%{wallet => check_in}`."
  def check_ins_by_wallet(wallets, fleet_id) do
    for profile <- agents_by_wallets!(wallets, load: [:check_ins]),
        check_in <- profile.check_ins,
        check_in.fleet_id == fleet_id,
        into: %{},
        do: {profile.wallet_address, check_in}
  end

  @doc """
  Whether `error` refused an agent's write because its pairing ended while
  the write was on its way (`RegentAgents.RequirePairing`, which names it in
  words only).
  """
  def unpaired?(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &unpaired?/1)
  def unpaired?(%Ash.Error.Changes.InvalidChanges{message: "active pairing required"}), do: true
  def unpaired?(_error), do: false

  @doc "Resolve current delegation from the shared pairing authority."
  def with_pairing(%Regents.Account.Actors.Agent{} = agent) do
    with {:ok, pairing} <- RegentAgents.Authority.resolve(Regents.Repo, agent.wallet_address),
         {:ok, account} <-
           Regents.Account.Accounts.get_by_privy_did(pairing.privy_user_id,
             actor: %Regents.Account.Actors.System{}
           ) do
      {:ok,
       %{
         agent
         | pairing_id: pairing.id,
           privy_user_id: pairing.privy_user_id,
           human_account_id: account && account.id,
           pairing:
             if(account,
               do: Regents.Account.Actors.Human.for_account(account),
               else: :person_not_here
             )
       }}
    end
  end

  @doc """
  Records that the agent checked in with the fleet, as `run` says: in a
  conversation (`%{"kind" => "session"}`) or on its schedule
  (`%{"kind" => "scheduled", "every_minutes" => minutes}`), with what blocks
  it when `run` says (`"blocker"`), which a check-in without one clears. An
  agent without a profile has nothing to record, which is `{:ok, nil}`.
  Otherwise the answer is the agent's check-ins with the fleet as they now
  stand.
  """
  def check_in(actor, fleet_id, run) do
    with_profile(actor, fn profile ->
      {action, arguments} =
        case run do
          %{"kind" => "session"} ->
            {:check_in_session, %{}}

          %{"kind" => "scheduled", "every_minutes" => minutes} ->
            {:check_in_scheduled, %{every_minutes: minutes}}
        end

      write(action, profile, fleet_id, Map.put(arguments, :blocker, run["blocker"]), actor)
    end)
  end

  @doc """
  Records that the agent just contributed to the fleet: a `:post`, a `:task`
  it joined or forked, a `:submit` of one, a `:review`, another `:workspace` write, a `:notebook` edit or a
  `:code` push. An agent without a profile has nothing to record.
  """
  def note_contribution(actor, fleet_id, kind) do
    with_profile(actor, &write(:note_contribution, &1, fleet_id, %{kind: kind}, actor))
  end

  @doc """
  Records a contribution that already stands elsewhere, in the graph, a
  notebook or the code store (`note_contribution/3`). What a person does is
  nobody's contribution, and a record that fails is logged, never raised.
  """
  def record_contribution(%Regents.Account.Actors.Agent{} = actor, fleet_id, kind) do
    case note_contribution(actor, fleet_id, kind) do
      {:ok, _check_in} ->
        :ok

      {:error, error} ->
        Logger.warning(
          "#{kind} contribution to #{fleet_id} not recorded: " <> Exception.message(error)
        )
    end
  end

  def record_contribution(_actor, _fleet_id, _kind), do: :ok

  @doc """
  Saves what the SIWA service said about the agent with this verified request
  onto its profile: its page in the agent registry, and the World ID person
  behind it with that person's agent count. The first person saved stays; a
  request naming nobody or someone else leaves them. Nothing is written when
  the request changes nothing, or when the agent has no profile yet;
  `ensure_profile` saves them when it makes one.

  A save that fails is `{:error, failure}` and is logged by the agent's
  pairing and the kind of failure alone: never the failure's words, which
  could hold the person's number, nor the agent's wallet. The agent's next
  request saves the same thing.
  """
  def save_listing(%Regents.Account.Actors.Agent{} = actor) do
    Regents.Keyfleet.Agents.AgentProfile
    |> Ash.Query.filter(wallet_address == ^actor.wallet_address)
    |> Ash.Query.filter(^listing_changes(actor))
    |> Ash.bulk_update(:save_listing, %{},
      actor: actor,
      strategy: :atomic,
      notify?: false,
      return_errors?: true,
      rollback_on_error?: false
    )
    |> case do
      %Ash.BulkResult{status: :success} ->
        :ok

      %Ash.BulkResult{errors: errors} ->
        listing_not_saved(actor, Ash.Error.to_error_class(errors))
    end
  rescue
    failure in [Postgrex.Error, DBConnection.ConnectionError] -> listing_not_saved(actor, failure)
  end

  defp listing_not_saved(actor, failure) do
    Logger.warning(
      "Saving the listing of the agent with pairing #{actor.pairing_id} failed: #{inspect(failure_kinds(failure))}"
    )

    {:error, failure}
  end

  defp failure_kinds(%{errors: [_ | _] = errors}), do: Enum.map(errors, & &1.__struct__)
  defp failure_kinds(failure), do: [failure.__struct__]

  # The profiles this request would change: a new registry page, or a person
  # where none is saved, or a new count for the person saved.
  defp listing_changes(%{registry_url: url, human_id: nil}),
    do: expr(fragment("? IS DISTINCT FROM ?::text", registry_url, ^url))

  defp listing_changes(%{registry_url: url, human_id: person, same_person_agent_count: count}) do
    expr(
      fragment("? IS DISTINCT FROM ?::text", registry_url, ^url) or is_nil(human_id) or
        (human_id == ^person and same_person_agent_count != ^count)
    )
  end

  @doc """
  How many agents are here in the fleet: holding one of its keys or an active
  shard of one, or paired with a person who holds one. `{:ok,
  count}`, or `{:error, failure}` when the database doesn't answer (see
  `Regents.Keyfleet.Count`).
  """
  def count_agents_here(fleet_id) do
    Regents.Keyfleet.Agents.AgentProfile
    |> Ash.Query.for_read(:here_in_fleet, %{fleet_id: fleet_id})
    |> Regents.Keyfleet.Count.of()
  end

  @doc """
  The keys the agents here act as (see `count_agents_here/1`), for each agent
  that checked in with the fleet or contributed to it since `since`.
  """
  def keys_active_since!(fleet_id, since) do
    Regents.Keyfleet.Agents.AgentProfile
    |> Ash.Query.for_read(:here_in_fleet, %{fleet_id: fleet_id})
    |> Ash.Query.filter(
      exists(
        check_ins,
        fleet_id == ^fleet_id and
          (last_check_in_at >= ^since or last_contribution_at >= ^since)
      )
    )
    |> Ash.read!()
    |> Enum.map(& &1.key)
  end

  @doc """
  How many of the agents here checked in with the fleet in the last 24 hours,
  as `{:ok, count}` or `{:error, failure}`.
  """
  def count_agents_checked_in_last_day(fleet_id) do
    Regents.Keyfleet.Agents.AgentProfile
    |> Ash.Query.for_read(:here_in_fleet, %{fleet_id: fleet_id})
    |> Ash.Query.filter(
      exists(
        check_ins,
        fleet_id == ^fleet_id and
          last_check_in_at >
            fragment("(statement_timestamp() AT TIME ZONE 'utc') - interval '1 day'")
      )
    )
    |> Regents.Keyfleet.Count.of()
  end

  @doc """
  Makes `bytes` the agent's picture, as it declared them (`Avatar.declare/1`)
  for its profile `profile_id`: checks them (`Avatar.check/2`), stores them in
  the bucket under a new key, then sets that key on the profile. Answers
  `{:ok, profile}`, `{:error, :mismatch | :unreadable}` for bytes that aren't
  what was declared or aren't such a picture, `{:error, :profile_not_found}`,
  or `{:error, reason}` when the bucket or the change fails. A picture stored
  whose change then fails is deleted again.
  """
  def store_avatar(actor, profile_id, declared, bytes) do
    with :ok <- Avatar.check(bytes, declared),
         {:ok, %{id: ^profile_id} = profile} <- get_my_profile(actor: actor),
         key = Avatar.new_key(profile_id, declared.content_type),
         :ok <- AvatarBucket.put(key, bytes, declared.content_type) do
      case set_avatar(profile, key, actor: actor) do
        {:ok, profile} ->
          {:ok, profile}

        {:error, error} ->
          Oban.insert!(DeleteAvatar.new(%{key: key}))
          {:error, error}
      end
    else
      {:ok, _other_or_none} -> {:error, :profile_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_profile(actor, fun) do
    case get_my_profile(actor: actor) do
      {:ok, nil} -> {:ok, nil}
      {:ok, profile} -> fun.(profile)
      {:error, error} -> {:error, error}
    end
  end

  defp write(action, profile, fleet_id, arguments, actor) do
    CheckIn
    |> Ash.Changeset.for_create(
      action,
      Map.merge(arguments, %{agent_profile_id: profile.id, fleet_id: fleet_id}),
      actor: actor
    )
    |> Ash.create()
  end
end
