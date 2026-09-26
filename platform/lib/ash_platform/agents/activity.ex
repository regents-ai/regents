defmodule AshPlatform.Agents.Activity do
  @moduledoc "One thing a paired agent did, in plain words, and where and when it did it."

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias AshPlatform.Actors.System

  @recent 50

  attributes do
    uuid_primary_key :id

    attribute :site, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 40
    end

    attribute :action, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200
    end

    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :paired_agent, AshPlatform.Agents.PairedAgent, allow_nil?: false
  end

  actions do
    create :log do
      public? false
      accept [:paired_agent_id, :site, :action, :occurred_at]
    end

    read :recent_for_agent do
      argument :paired_agent_id, :uuid, allow_nil?: false
      filter expr(paired_agent_id == ^arg(:paired_agent_id))
      prepare build(sort: [occurred_at: :desc, id: :asc], limit: @recent)
    end
  end

  policies do
    policy action(:log) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action(:recent_for_agent) do
      authorize_if AshPlatform.Accounts.Checks.HumanActor
    end

    policy action(:recent_for_agent) do
      authorize_if expr(paired_agent.human_account_id == ^actor(:human_account_id))
    end
  end

  postgres do
    table "agent_activities"
    repo(AshPlatform.Repo)

    references do
      reference(:paired_agent, on_delete: :delete)
    end

    custom_indexes do
      index([:paired_agent_id, :occurred_at])
    end
  end

  @doc "Records something an agent did on this site."
  def record(agent, action, occurred_at) do
    __MODULE__
    |> Ash.Changeset.for_create(
      :log,
      %{
        paired_agent_id: agent.id,
        site: "Regents Labs",
        action: action,
        occurred_at: occurred_at
      },
      actor: %System{}
    )
    |> Ash.create()
  end
end
