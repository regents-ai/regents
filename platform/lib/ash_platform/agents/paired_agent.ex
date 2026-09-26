defmodule AshPlatform.Agents.PairedAgent.Actions.Pair do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias AshPlatform.Actors.System
  alias AshPlatform.Agents.{PairedAgent, PairingCode}

  @impl true
  def run(%{arguments: arguments}, _opts, %{actor: %System{} = actor}) do
    result =
      Ash.DataLayer.transaction(PairedAgent, fn ->
        now = clock().()

        with {:ok, pairing_code} <- pairing_code(arguments.code, actor),
             :ok <- admit_code(pairing_code, now),
             {:ok, agent} <- create_agent(pairing_code, arguments, now, actor),
             {:ok, _pairing_code} <- consume(pairing_code, now, actor) do
          agent
        else
          {:error, error} -> Ash.DataLayer.rollback(PairedAgent, error)
        end
      end)

    case result do
      {:ok, agent} ->
        PairedAgent.broadcast(agent.human_account_id)
        {:ok, agent}

      {:error, _error} ->
        {:error, "pairing code could not be used"}
    end
  end

  def run(_input, _opts, _context), do: {:error, "verified system context is required"}

  defp pairing_code(code, actor) do
    PairingCode
    |> Ash.Query.for_read(:by_code_hash, %{code_hash: PairingCode.hash(String.trim(code))},
      actor: actor
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one()
  end

  defp admit_code(nil, _now), do: {:error, :invalid_pairing_code}

  defp admit_code(pairing_code, now) do
    if is_nil(pairing_code.used_at) and DateTime.compare(pairing_code.expires_at, now) == :gt,
      do: :ok,
      else: {:error, :invalid_pairing_code}
  end

  defp create_agent(pairing_code, arguments, now, actor) do
    PairedAgent
    |> Ash.Changeset.for_create(
      :record,
      %{
        human_account_id: pairing_code.human_account_id,
        wallet: arguments.wallet,
        name: arguments.name,
        harness: arguments.harness,
        paired_at: now,
        last_contact_at: now
      },
      actor: actor
    )
    |> Ash.create()
  end

  defp consume(pairing_code, now, actor) do
    pairing_code
    |> Ash.Changeset.for_update(:consume, %{used_at: now}, actor: actor)
    |> Ash.update()
  end

  defp clock, do: Application.fetch_env!(:ash_platform, :agent_pairing_clock)
end

defmodule AshPlatform.Agents.PairedAgent.Actions.CheckIn do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias AshPlatform.Actors.System
  alias AshPlatform.Agents.PairedAgent

  @impl true
  def run(%{arguments: %{wallet: wallet}}, _opts, %{actor: %System{} = actor}) do
    now = clock().()

    result =
      Ash.DataLayer.transaction(PairedAgent, fn ->
        with {:ok, agent} when not is_nil(agent) <- by_wallet(wallet, actor),
             {:ok, agent} <- touch(agent, now, actor) do
          agent
        else
          {:ok, nil} -> Ash.DataLayer.rollback(PairedAgent, :not_paired)
          {:error, error} -> Ash.DataLayer.rollback(PairedAgent, error)
        end
      end)

    with {:ok, agent} <- result do
      PairedAgent.broadcast(agent.human_account_id)
      {:ok, agent}
    end
  end

  def run(_input, _opts, _context), do: {:error, "verified system context is required"}

  defp by_wallet(wallet, actor) do
    PairedAgent
    |> Ash.Query.for_read(:by_wallet, %{wallet: wallet}, actor: actor)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one()
  end

  defp touch(agent, now, actor) do
    agent
    |> Ash.Changeset.for_update(:touch, %{last_contact_at: now}, actor: actor)
    |> Ash.update()
  end

  defp clock, do: Application.fetch_env!(:ash_platform, :agent_pairing_clock)
end

defmodule AshPlatform.Agents.PairedAgent do
  @moduledoc """
  An agent a person paired with their account. The agent proved it holds its
  key through SIWA; the name and runtime are what it said about itself, and
  the person may correct the runtime.
  """

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :wallet, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 80, trim?: true
    end

    attribute :harness, AshPlatform.Agents.Harness, allow_nil?: false, public?: true
    attribute :paired_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_contact_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  actions do
    action :pair, :struct do
      constraints instance_of: __MODULE__
      argument :code, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 128]
      argument :wallet, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :harness, AshPlatform.Agents.Harness, allow_nil?: false
      run AshPlatform.Agents.PairedAgent.Actions.Pair
    end

    action :check_in, :struct do
      constraints instance_of: __MODULE__
      argument :wallet, :string, allow_nil?: false
      run AshPlatform.Agents.PairedAgent.Actions.CheckIn
    end

    read :read do
      primary? true
      public? false
    end

    create :record do
      public? false
      accept [:human_account_id, :wallet, :name, :harness, :paired_at, :last_contact_at]
    end

    read :by_wallet do
      public? false
      get? true
      argument :wallet, :string, allow_nil?: false
      filter expr(wallet == ^arg(:wallet))
    end

    read :mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [paired_at: :desc, id: :asc])
    end

    read :mine_by_id do
      get_by :id
      filter expr(human_account_id == ^actor(:human_account_id))
    end

    update :touch do
      public? false
      accept [:last_contact_at]
    end

    update :change_harness do
      accept [:harness]
      require_atomic? false
      change after_action(&announce/3)
    end

    destroy :unpair do
      require_atomic? false
      change after_action(&announce/3)
    end
  end

  policies do
    policy action([:pair, :check_in, :record, :by_wallet, :touch]) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action(:read) do
      authorize_if AshPlatform.Checks.SystemActor
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    policy action([:mine, :mine_by_id, :change_harness, :unpair]) do
      authorize_if AshPlatform.Accounts.Checks.HumanActor
    end

    policy action([:mine, :mine_by_id, :change_harness, :unpair]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :unique_wallet, [:wallet]
  end

  postgres do
    table "paired_agents"
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:human_account_id])
    end
  end

  defp announce(_changeset, agent, _context) do
    broadcast(agent.human_account_id)
    {:ok, agent}
  end

  @doc "Tells an open Account page of this person that their agents changed."
  def broadcast(human_account_id) do
    Phoenix.PubSub.broadcast(AshPlatform.PubSub, topic(human_account_id), :agents_changed)
  end

  def topic(human_account_id), do: "paired_agents:#{human_account_id}"
end
