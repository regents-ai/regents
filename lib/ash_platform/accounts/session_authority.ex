defmodule AshPlatform.Accounts.SessionAuthority do
  @moduledoc """
  Durable server authority for one local human session lineage.

  A lineage identifier carried in a browser session is only a lookup key. It is
  authority solely while this table holds an unrevoked row bound to the presented
  account. Revocation is terminal: the row is retained forever as a tombstone at
  the reserved maximum generation, so a sign-in whose verification finishes after
  a logout can never establish authority behind that logout.

  Every path takes locks in one order — the lineage advisory lock, then the
  authority row, then account rows in ascending id order — so no two paths can
  deadlock and no revoke can be lost to a concurrent sign-in.
  """

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias AshPlatform.Actors.System
  alias AshPlatform.Repo

  @tombstone_generation 9_223_372_036_854_775_807
  @system %System{}

  actions do
    read :by_lineage do
      public? false
      get? true
      argument :lineage, :uuid, allow_nil?: false
      filter expr(lineage == ^arg(:lineage))
    end

    create :establish do
      public? false
      accept [:lineage, :human_account_id]
    end

    update :rebind do
      public? false
      require_atomic? false
      accept [:human_account_id, :generation]
    end

    update :revoke do
      public? false
      require_atomic? false
      accept []
      change set_attribute(:generation, @tombstone_generation)
      change set_attribute(:revoked_at, &DateTime.utc_now/0)
    end

    create :tombstone do
      public? false
      accept [:lineage]
      change set_attribute(:generation, @tombstone_generation)
      change set_attribute(:revoked_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy action([:by_lineage, :establish, :rebind, :revoke, :tombstone]) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  attributes do
    attribute :lineage, :uuid do
      primary_key? true
      allow_nil? false
      writable? true
      sensitive? true
    end

    attribute :generation, :integer, allow_nil?: false, default: 0
    attribute :revoked_at, :utc_datetime_usec
    timestamps()
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      attribute_type :integer
    end
  end

  postgres do
    table "session_authorities"
    repo(AshPlatform.Repo)

    references do
      reference(:human_account, on_delete: :restrict, on_update: :restrict)
    end

    check_constraints do
      check_constraint(:generation, "session_authorities_generation_non_negative",
        check: "generation >= 0",
        message: "must not be negative"
      )

      check_constraint(
        [:generation, :revoked_at, :human_account_id],
        "session_authorities_terminal_revocation",
        check:
          "(revoked_at IS NULL AND human_account_id IS NOT NULL AND generation < 9223372036854775807) OR (revoked_at IS NOT NULL AND generation = 9223372036854775807)",
        message: "revocation is terminal"
      )
    end
  end

  @doc "The generation reserved for terminal tombstones; active authority never reaches it."
  def tombstone_generation, do: @tombstone_generation

  @doc "A fresh server-generated lineage candidate for a sign-in attempt."
  def mint_lineage, do: Ash.UUID.generate()

  @doc """
  The authority a consumer captures at authorization time.

  Returns `nil` unless the presented lineage still holds unrevoked authority over
  the presented account.
  """
  def capture(lineage, human_account_id)
      when is_binary(lineage) and is_integer(human_account_id) do
    case read(lineage) do
      {:ok, %{revoked_at: nil, human_account_id: ^human_account_id} = authority} ->
        authority

      _superseded ->
        nil
    end
  end

  def capture(_lineage, _human_account_id), do: nil

  @doc """
  Binds `lineage` to `human_account_id` and runs `protected_write` under the
  revalidated authority in the same repository transaction.

  A first binding establishes generation zero, a same-account binding preserves
  the lineage and its generation, and an account switch advances the generation
  and rebinds. A revoked lineage fails closed.
  """
  def bind(lineage, human_account_id, protected_write)
      when is_binary(lineage) and is_integer(human_account_id) do
    transaction(fn ->
      lock_lineage(lineage)
      current = locked(lineage)
      lock_accounts([human_account_id | account_ids(current)])

      with {:ok, authority} <- rebind(current, lineage, human_account_id) do
        revalidate(authority, protected_write)
      end
    end)
  end

  @doc """
  Runs `protected_write` only while `capture` is still the current authority,
  revalidated under the authority row lock inside the same repository transaction
  and process as the write.
  """
  def authorize(capture, protected_write)

  def authorize(nil, _protected_write), do: {:error, :session_revoked}

  def authorize(%{lineage: lineage} = capture, protected_write) do
    transaction(fn ->
      lock_lineage(lineage)
      revalidate(capture, protected_write)
    end)
  end

  @doc """
  Revokes `lineage` before any local session is cleared.

  Keyed only by the lineage, never by presented account or generation metadata.
  The first active revoke advances the generation to the reserved tombstone and
  records the revocation atomically, a missing lineage materializes a retained
  tombstone, and every later revoke is an exact no-op.
  """
  def revoke(lineage)

  def revoke(nil), do: {:ok, nil}

  def revoke(lineage) when is_binary(lineage) do
    transaction(fn ->
      lock_lineage(lineage)
      current = locked(lineage)
      lock_accounts(account_ids(current))
      revoke_locked(current, lineage)
    end)
  end

  defp rebind(nil, lineage, human_account_id),
    do: create(:establish, %{lineage: lineage, human_account_id: human_account_id})

  defp rebind(%{revoked_at: nil, human_account_id: id} = authority, _lineage, id),
    do: {:ok, authority}

  defp rebind(%{revoked_at: nil, generation: generation}, _lineage, _human_account_id)
       when generation >= @tombstone_generation - 1,
       do: {:error, :session_generation_exhausted}

  defp rebind(%{revoked_at: nil} = authority, _lineage, human_account_id),
    do:
      update(authority, :rebind, %{
        human_account_id: human_account_id,
        generation: authority.generation + 1
      })

  defp rebind(%{}, _lineage, _human_account_id), do: {:error, :session_revoked}

  defp revoke_locked(nil, lineage), do: create(:tombstone, %{lineage: lineage})

  defp revoke_locked(%{revoked_at: nil} = authority, _lineage),
    do: update(authority, :revoke, %{})

  defp revoke_locked(%{} = authority, _lineage), do: {:ok, authority}

  defp revalidate(
         %{lineage: lineage, generation: generation, human_account_id: account_id},
         protected_write
       ) do
    case locked(lineage) do
      %{generation: ^generation, human_account_id: ^account_id, revoked_at: nil} = current ->
        protected_write.(current)

      _superseded ->
        {:error, :session_revoked}
    end
  end

  defp read(lineage) do
    __MODULE__
    |> Ash.Query.for_read(:by_lineage, %{lineage: lineage}, actor: @system)
    |> Ash.read_one()
  end

  defp locked(lineage) do
    __MODULE__
    |> Ash.Query.for_read(:by_lineage, %{lineage: lineage}, actor: @system)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!()
  end

  defp create(action, params) do
    __MODULE__
    |> Ash.Changeset.for_create(action, params, actor: @system)
    |> Ash.create()
  end

  defp update(authority, action, params) do
    authority
    |> Ash.Changeset.for_update(action, params, actor: @system)
    |> Ash.update()
  end

  # The advisory lock serializes sign-in and logout on one lineage even before
  # its authority row exists, so neither linearization can lose the revoke.
  defp lock_lineage(lineage) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1::text), 0)", [lineage])
  end

  defp lock_accounts(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(&lock_account/1)
  end

  defp lock_account(id) do
    Repo.query!("SELECT id FROM platform.platform_human_users WHERE id = $1 FOR UPDATE", [id])
  end

  defp account_ids(nil), do: []
  defp account_ids(%{human_account_id: id}), do: [id]

  defp transaction(operation) do
    result =
      Ash.DataLayer.transaction(__MODULE__, fn ->
        case operation.() do
          {:error, error} -> Ash.DataLayer.rollback(__MODULE__, error)
          committed -> committed
        end
      end)

    case result do
      {:ok, committed} -> committed
      {:error, error} -> {:error, error}
    end
  end
end
