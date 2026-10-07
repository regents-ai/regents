defmodule RegentAgents.PairingCode.Issued do
  @moduledoc "A code just made, shown to the person once."
  @enforce_keys [:code, :issued_at, :expires_at]
  defstruct [:code, :issued_at, :expires_at]
end

defmodule RegentAgents.PairingCode.Actions.Issue do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias RegentAgents.{PairingCode, Person}

  @ttl_seconds 600

  @impl true
  def run(_input, _opts, %{actor: %Person{} = actor}) do
    code = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, @ttl_seconds, :second)

    Ash.DataLayer.transaction(PairingCode, fn ->
      RegentAgents.lock(actor.privy_user_id)

      with {:ok, codes} <- Ash.read(PairingCode, action: :for_person, actor: actor),
           :ok <- discard(spent(codes, now), actor),
           {:ok, _record} <- store(code, now, expires_at, actor) do
        %PairingCode.Issued{code: code, issued_at: now, expires_at: expires_at}
      else
        {:error, error} -> Ash.DataLayer.rollback(PairingCode, error)
      end
    end)
  end

  def run(_input, _opts, _context), do: {:error, "a signed-in person is required"}

  # Codes that can no longer pair: used, or expired.
  defp spent(codes, now),
    do: Enum.reject(codes, &(is_nil(&1.used_at) and DateTime.after?(&1.expires_at, now)))

  defp discard([], _actor), do: :ok

  defp discard(codes, actor) do
    ids = Enum.map(codes, & &1.id)

    PairingCode
    |> Ash.Query.for_read(:for_person, %{}, actor: actor)
    |> Ash.Query.filter(id in ^ids)
    |> Ash.bulk_destroy(:discard, %{}, actor: actor, strategy: :atomic, return_errors?: true)
    |> case do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end

  defp store(code, now, expires_at, actor) do
    PairingCode
    |> Ash.Changeset.for_create(
      :store,
      %{code_hash: PairingCode.hash(code), issued_at: now, expires_at: expires_at},
      actor: actor
    )
    |> Ash.create()
  end
end

defmodule RegentAgents.PairingCode do
  @moduledoc """
  A short-lived code a signed-in person hands their agent. Only its hash is
  kept. Each works once, for ten minutes, on any Regent site. A new code leaves
  the person's earlier ones working until they expire. A person may make as
  many as they like; one account holds at most 100 paired agents.
  """

  use Ash.Resource,
    otp_app: :regent_agents,
    domain: RegentAgents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentAgents.repo/2
    schema "regent_agents"
    table "pairing_codes"
    migrate? false
  end

  attributes do
    uuid_primary_key :id
    attribute :privy_user_id, :string, allow_nil?: false, sensitive?: true

    attribute :code_hash, :string do
      allow_nil? false
      sensitive? true
      constraints min_length: 64, max_length: 64, match: ~r/\A[0-9a-f]{64}\z/
    end

    attribute :issued_at, :utc_datetime_usec, allow_nil?: false
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false
    attribute :used_at, :utc_datetime_usec
    timestamps()
  end

  actions do
    action :issue, :struct do
      constraints instance_of: RegentAgents.PairingCode.Issued
      run RegentAgents.PairingCode.Actions.Issue
    end

    create :store do
      public? false
      accept [:code_hash, :issued_at, :expires_at]
      change set_attribute(:privy_user_id, actor(:privy_user_id))
    end

    read :for_person do
      public? false
      filter expr(privy_user_id == ^actor(:privy_user_id))
      prepare build(sort: [issued_at: :desc])
    end

    read :by_code_hash do
      public? false
      get? true
      argument :code_hash, :string, allow_nil?: false
      filter expr(code_hash == ^arg(:code_hash))
    end

    update :consume do
      public? false
      require_atomic? false
      accept [:used_at]
    end

    destroy :discard do
      public? false
    end
  end

  policies do
    policy action([:issue, :store, :for_person, :discard]) do
      authorize_if RegentAgents.Checks.Person
    end

    policy action(:discard) do
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end

    policy action([:by_code_hash, :consume]) do
      authorize_if RegentAgents.Checks.Agent
    end
  end

  identities do
    identity :unique_code_hash, [:code_hash]
  end

  def hash(code), do: :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
end
