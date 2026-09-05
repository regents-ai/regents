defmodule AshPlatform.Formation.AgentLink.Actions.Claim do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias AshPlatform.Actors.System
  alias AshPlatform.Formation.{AgentLink, AgentPairingCode}

  @impl true
  def run(%{arguments: arguments}, _opts, %{actor: %System{} = actor}) do
    with {:ok, identity} <- verified_identity(arguments.identity),
         code when code != "" <- String.trim(arguments.code) do
      claim(arguments.regent_id, code, identity, actor)
    else
      _ -> {:error, "pairing code could not be used"}
    end
  end

  def run(_input, _opts, _context), do: {:error, "verified system context is required"}

  defp claim(regent_id, code, identity, actor) do
    result =
      Ash.DataLayer.transaction(AgentLink, fn ->
        now = clock().()

        with {:ok, pairing_code} <- pairing_code(code, actor),
             :ok <- admit_code(pairing_code, regent_id, now),
             {:ok, link} <- create_link(pairing_code, identity, now, actor),
             {:ok, _pairing_code} <- consume(pairing_code, now, actor) do
          link
        else
          {:error, error} -> Ash.DataLayer.rollback(AgentLink, error)
        end
      end)

    case result do
      {:ok, link} -> {:ok, link}
      {:error, _error} -> {:error, "pairing code could not be used"}
    end
  end

  defp pairing_code(code, actor) do
    AgentPairingCode
    |> Ash.Query.for_read(:by_code_hash, %{code_hash: code_hash(code)}, actor: actor)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one()
  end

  defp admit_code(nil, _regent_id, _now), do: {:error, :invalid_pairing_code}

  defp admit_code(pairing_code, regent_id, now) do
    if pairing_code.regent_id == regent_id and is_nil(pairing_code.used_at) and
         DateTime.compare(pairing_code.expires_at, now) == :gt do
      :ok
    else
      {:error, :invalid_pairing_code}
    end
  end

  defp create_link(pairing_code, identity, now, actor) do
    AgentLink
    |> Ash.Changeset.for_create(
      :pair,
      Map.merge(identity, %{
        regent_id: pairing_code.regent_id,
        human_account_id: pairing_code.human_account_id,
        paired_at: now
      }),
      actor: actor
    )
    |> Ash.create()
  end

  defp consume(pairing_code, now, actor) do
    pairing_code
    |> Ash.Changeset.for_update(:consume, %{used_at: now}, actor: actor)
    |> Ash.update()
  end

  defp verified_identity(%{
         agent_id: agent_id,
         registry_address: registry_address,
         token_id: token_id,
         wallet: wallet
       })
       when is_binary(agent_id) and is_binary(registry_address) and is_binary(token_id) and
              is_binary(wallet) do
    registry_address = String.downcase(registry_address)
    wallet = String.downcase(wallet)

    if valid_identifier?(agent_id) and valid_identifier?(token_id) and
         valid_address?(registry_address) and valid_address?(wallet) do
      {:ok,
       %{
         agent_id: String.trim(agent_id),
         registry_address: registry_address,
         token_id: String.trim(token_id),
         wallet: wallet
       }}
    else
      {:error, :invalid_identity}
    end
  end

  defp verified_identity(_identity), do: {:error, :invalid_identity}

  defp valid_identifier?(value),
    do: String.trim(value) != "" and String.length(value) <= 255

  defp valid_address?(value), do: Regex.match?(~r/\A0x[0-9a-f]{40}\z/, value)

  defp code_hash(code), do: :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)

  defp clock,
    do: Application.get_env(:ash_platform, :agent_pairing_clock, &DateTime.utc_now/0)
end

defmodule AshPlatform.Formation.AgentLink do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Formation,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :agent_id, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 255, trim?: true
    end

    attribute :registry_address, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :token_id, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 255, trim?: true
    end

    attribute :wallet, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :paired_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    belongs_to :regent, AshPlatform.Formation.Regent do
      allow_nil? false
    end
  end

  actions do
    action :claim, :struct do
      constraints instance_of: AshPlatform.Formation.AgentLink
      argument :regent_id, :uuid, allow_nil?: false
      argument :code, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 128]
      argument :identity, :map, allow_nil?: false
      run AshPlatform.Formation.AgentLink.Actions.Claim
    end

    create :pair do
      public? false

      accept [
        :human_account_id,
        :regent_id,
        :agent_id,
        :registry_address,
        :token_id,
        :wallet,
        :paired_at
      ]
    end

    read :mine_for_regent do
      argument :regent_id, :uuid, allow_nil?: false

      filter expr(
               regent_id == ^arg(:regent_id) and
                 human_account_id == ^actor(:human_account_id)
             )

      prepare build(sort: [paired_at: :asc, id: :asc])
    end

    destroy :revoke do
      require_atomic? false
    end
  end

  policies do
    policy action([:claim, :pair]) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action([:mine_for_regent, :revoke]) do
      authorize_if AshPlatform.Formation.Checks.HumanActor
    end

    policy action([:mine_for_regent, :revoke]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :unique_agent_id, [:agent_id]
    identity :unique_registry_token, [:registry_address, :token_id]
  end

  postgres do
    table "agent_links"
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:human_account_id])
      index([:regent_id])
    end
  end
end
