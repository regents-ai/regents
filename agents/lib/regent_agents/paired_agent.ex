defmodule RegentAgents.PairedAgent.Actions.Pair do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias RegentAgents.{Agent, PairedAgent, PairingCode}

  @impl true
  def run(%{arguments: arguments}, _opts, %{actor: %Agent{} = actor}) do
    result =
      Ash.DataLayer.transaction(PairedAgent, fn ->
        now = DateTime.utc_now()

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
        RegentAgents.announce(agent.privy_user_id)
        {:ok, agent}

      {:error, _error} ->
        {:error, "pairing code could not be used"}
    end
  end

  def run(_input, _opts, _context), do: {:error, "a verified agent is required"}

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
        privy_user_id: pairing_code.privy_user_id,
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
end

defmodule RegentAgents.PairedAgent.Actions.CheckIn do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias RegentAgents.{Agent, PairedAgent}

  @impl true
  def run(_input, _opts, %{actor: %Agent{} = actor}) do
    result =
      Ash.DataLayer.transaction(PairedAgent, fn ->
        with {:ok, agent} when not is_nil(agent) <- by_wallet(actor),
             {:ok, agent} <- touch(agent, actor) do
          agent
        else
          {:ok, nil} -> Ash.DataLayer.rollback(PairedAgent, :not_paired)
          {:error, error} -> Ash.DataLayer.rollback(PairedAgent, error)
        end
      end)

    with {:ok, agent} <- result do
      RegentAgents.announce(agent.privy_user_id)
      {:ok, agent}
    end
  end

  def run(_input, _opts, _context), do: {:error, "a verified agent is required"}

  defp by_wallet(actor) do
    PairedAgent
    |> Ash.Query.for_read(:by_wallet, %{}, actor: actor)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one()
  end

  defp touch(agent, actor) do
    agent
    |> Ash.Changeset.for_update(:touch, %{last_contact_at: DateTime.utc_now()}, actor: actor)
    |> Ash.update()
  end
end

defmodule RegentAgents.PairedAgent do
  @moduledoc """
  An agent a person paired with their account. The agent proved it holds its
  key through SIWA; the name and runtime are what it said about itself, and
  the person may correct the runtime. One key belongs to one person.
  """

  use Ash.Resource,
    otp_app: :regent_agents,
    domain: RegentAgents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentAgents.repo/2
    schema "regent_agents"
    table "paired_agents"
    migrate? false
  end

  attributes do
    uuid_primary_key :id
    attribute :privy_user_id, :string, allow_nil?: false, sensitive?: true

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

    attribute :harness, RegentAgents.Harness, allow_nil?: false, public?: true
    attribute :paired_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_contact_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  actions do
    action :pair, :struct do
      constraints instance_of: __MODULE__
      argument :code, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 128]
      argument :name, :string, allow_nil?: false
      argument :harness, RegentAgents.Harness, allow_nil?: false
      run RegentAgents.PairedAgent.Actions.Pair
    end

    action :check_in, :struct do
      constraints instance_of: __MODULE__
      run RegentAgents.PairedAgent.Actions.CheckIn
    end

    read :read do
      primary? true
      public? false
    end

    create :record do
      public? false
      accept [:privy_user_id, :name, :harness, :paired_at, :last_contact_at]
      change set_attribute(:wallet, actor(:wallet))
    end

    read :by_wallet do
      public? false
      get? true
      filter expr(wallet == ^actor(:wallet))
    end

    read :mine do
      filter expr(privy_user_id == ^actor(:privy_user_id))
      prepare build(sort: [paired_at: :desc, id: :asc])
    end

    read :mine_by_id do
      get_by :id
      filter expr(privy_user_id == ^actor(:privy_user_id))
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
    policy action([:pair, :check_in, :record, :by_wallet]) do
      authorize_if RegentAgents.Checks.Agent
    end

    policy action(:touch) do
      authorize_if expr(wallet == ^actor(:wallet))
    end

    policy action(:read) do
      authorize_if expr(wallet == ^actor(:wallet))
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end

    policy action([:mine, :mine_by_id, :change_harness, :unpair]) do
      authorize_if RegentAgents.Checks.Person
    end

    policy action([:mine, :mine_by_id, :change_harness, :unpair]) do
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end

  identities do
    identity :unique_wallet, [:wallet]
  end

  defp announce(_changeset, agent, _context) do
    RegentAgents.announce(agent.privy_user_id)
    {:ok, agent}
  end
end
