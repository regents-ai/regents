defmodule Regents.Staking.ProtocolReading do
  @moduledoc "The shared, restart-safe public staking projection and its retained deposit history."

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Staking,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    defaults [:read]

    read :current do
      prepare build(select: [:id, :snapshot])
    end

    create :record do
      accept [:id, :history, :snapshot]
    end

    update :replace do
      accept [:history, :snapshot]
      change optimistic_lock(:revision)
    end
  end

  policies do
    policy action(:current) do
      authorize_if always()
    end

    policy action([:read, :record, :replace]) do
      authorize_if Regents.Checks.SystemActor
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false
    attribute :history, :map, allow_nil?: false
    attribute :snapshot, :map, allow_nil?: false
    attribute :revision, :integer, allow_nil?: false, default: 1
    timestamps()
  end

  postgres do
    table "staking_protocol_readings"
    repo(Regents.Repo)
  end
end
