defmodule AshPlatform.Agents.PairingCode.Issued do
  @moduledoc false
  @enforce_keys [:code, :expires_at]
  defstruct [:code, :expires_at]
end

defmodule AshPlatform.Agents.PairingCode.Actions.Issue do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias AshPlatform.Actors.Human
  alias AshPlatform.Agents.PairingCode

  @ttl_seconds 600
  @rate_limit_seconds 60

  @impl true
  def run(_input, _opts, %{actor: %Human{} = actor}) do
    code = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
    now = clock().()
    expires_at = DateTime.add(now, @ttl_seconds, :second)

    Ash.DataLayer.transaction(PairingCode, fn ->
      with {:ok, _result} <- lock_human(actor.human_account_id),
           {:ok, existing} <- pairing_code(actor),
           :ok <- admit_issue(existing, now),
           {:ok, _record} <- store(existing, code, now, expires_at, actor) do
        %PairingCode.Issued{code: code, expires_at: expires_at}
      else
        {:error, error} -> Ash.DataLayer.rollback(PairingCode, error)
      end
    end)
  end

  def run(_input, _opts, _context), do: {:error, "a signed-in human is required"}

  defp lock_human(human_account_id) do
    AshPlatform.Repo.query("SELECT pg_advisory_xact_lock($1)", [human_account_id])
  end

  defp pairing_code(actor) do
    PairingCode
    |> Ash.Query.for_read(:for_human, %{}, actor: actor)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one()
  end

  defp admit_issue(nil, _now), do: :ok

  defp admit_issue(%{issued_at: issued_at}, now) do
    if DateTime.diff(now, issued_at, :second) >= @rate_limit_seconds,
      do: :ok,
      else:
        {:error,
         Ash.Error.Invalid.Unavailable.exception(resource: PairingCode, reason: :issued_recently)}
  end

  defp store(nil, code, now, expires_at, actor) do
    PairingCode
    |> Ash.Changeset.for_create(
      :store,
      %{
        human_account_id: actor.human_account_id,
        code_hash: PairingCode.hash(code),
        issued_at: now,
        expires_at: expires_at
      },
      actor: actor
    )
    |> Ash.create()
  end

  defp store(existing, code, now, expires_at, actor) do
    existing
    |> Ash.Changeset.for_update(
      :replace,
      %{code_hash: PairingCode.hash(code), issued_at: now, expires_at: expires_at, used_at: nil},
      actor: actor
    )
    |> Ash.update()
  end

  defp clock, do: Application.fetch_env!(:ash_platform, :agent_pairing_clock)
end

defmodule AshPlatform.Agents.PairingCode do
  @moduledoc """
  The one short-lived code a signed-in person hands their agent. Only its hash
  is kept; an agent that signs a request with it joins the person's account.
  """

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

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

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  actions do
    action :issue, :struct do
      constraints instance_of: AshPlatform.Agents.PairingCode.Issued
      run AshPlatform.Agents.PairingCode.Actions.Issue
    end

    create :store do
      public? false
      accept [:human_account_id, :code_hash, :issued_at, :expires_at]
    end

    read :for_human do
      public? false
      get? true
      filter expr(human_account_id == ^actor(:human_account_id))
    end

    read :by_code_hash do
      public? false
      get? true
      argument :code_hash, :string, allow_nil?: false
      filter expr(code_hash == ^arg(:code_hash))
    end

    update :replace do
      public? false
      require_atomic? false
      accept [:code_hash, :issued_at, :expires_at, :used_at]
    end

    update :consume do
      public? false
      require_atomic? false
      accept [:used_at]
    end
  end

  policies do
    policy action([:issue, :store, :for_human, :replace]) do
      authorize_if AshPlatform.Accounts.Checks.HumanActor
    end

    policy action([:store, :for_human, :replace]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    policy action([:by_code_hash, :consume]) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_human_account, [:human_account_id]
    identity :unique_code_hash, [:code_hash]
  end

  postgres do
    table "agent_pairing_codes"
    repo(AshPlatform.Repo)
  end

  def hash(code), do: :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
end
