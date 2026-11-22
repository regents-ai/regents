defmodule Regents.Keyfleet.Code.Push do
  @moduledoc """
  One branch or tag a key's holder moved in one project's repository: which
  key, the wallet holding it, the branch or tag and the commit it now points
  at. The store accepted each one recorded (`RegentsWeb.Keyfleet.Plugs.CodeGateway`).
  They are read as the code is, by the fleet's members (`Regents.Keyfleet.Access`,
  `:code`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Code,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "code_pushes"
    schema("keyfleet_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:fleet_id, :project, :pushed_at])
    end
  end

  actions do
    create :record do
      accept [
        :fleet_id,
        :project,
        :token_id,
        :wallet,
        :ref,
        :head,
        :acting_agent_wallet,
        :beneficiary_privy_user_id,
        :agent_pairing_id
      ]
    end

    # Every push to one project's repository, for its deletion.
    read :of_project do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))
    end

    destroy :forget do
      public? false
    end

    read :recent do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))
      prepare build(sort: [pushed_at: :desc], limit: 10)
    end

    # The fleet's pushes to every project's repository from just past
    # `before_at` and `before_id`, newest first, `limit` at most. `keys` and
    # `wallet` keep the pushes made as those Keys, or by that wallet holding
    # the Key or acting for it (`Regents.Keyfleet.Preparations.DoneBy`).
    read :pushed_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_at, :utc_datetime_usec, allow_nil?: false
      argument :before_id, :uuid
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 200]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id))

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [pushed_at: :desc, id: :asc], before: [:before_at, :before_id]}

      prepare {Regents.Keyfleet.Preparations.DoneBy,
               key: :token_id, wallet: [:wallet, :acting_agent_wallet]}

      prepare build(select: [:id, :fleet_id, :project, :token_id, :ref, :head, :pushed_at])
    end

    # The pushes `ids` names in one project's repository: who sent the
    # commits each one first brought (`Regents.Keyfleet.Code.Commit`).
    read :of_ids do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      argument :ids, {:array, :uuid}, allow_nil?: false, constraints: [max_length: 100]

      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project) and id in ^arg(:ids))
    end

    # The push with `id`, for the job that records the commits it brought.
    read :one do
      public? false
      get_by [:id]
    end

    # Every push to a branch, oldest first, for `Regents.Keyfleet.Code.Sent.backfill/0`.
    read :branches do
      public? false
      filter expr(fragment("starts_with(?, 'refs/heads/')", ref))
      prepare build(sort: [pushed_at: :asc])
    end

    # The newest tip of each branch before `before`, at most 100 of them: a
    # push brought the commits its tip reaches and none of these reach.
    read :tips_before do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      argument :before, :utc_datetime_usec, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and project == ^arg(:project) and
                 pushed_at < ^arg(:before) and fragment("starts_with(?, 'refs/heads/')", ref)
             )

      prepare build(
                distinct: [:ref],
                distinct_sort: [pushed_at: :desc],
                limit: 100
              )
    end
  end

  policies do
    policy action([:recent, :of_ids, :pushed_before]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :code, scope: :fleet_id}
    end

    policy action([:record, :of_project, :forget, :one, :branches, :tips_before]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string
    attribute :beneficiary_privy_user_id, :string, sensitive?: true
    attribute :agent_pairing_id, :uuid
    uuid_primary_key :id
    attribute :fleet_id, :string, allow_nil?: false, public?: true
    attribute :project, :string, allow_nil?: false, public?: true
    attribute :token_id, :integer, allow_nil?: false, public?: true
    attribute :wallet, :string, allow_nil?: false, public?: true
    attribute :ref, :string, allow_nil?: false, public?: true
    attribute :head, :string, allow_nil?: false, public?: true
    create_timestamp :pushed_at, public?: true
  end
end
