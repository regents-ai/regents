defmodule Regents.Techtree.Projects.Project do
  @moduledoc """
  One project Techtree delivered to a customer's account — either by the team
  or autonomously via Uplift Factory's `OrderBridge`: the verified package
  kept whole (`uplift-package/1` for Skills, `uplift-package/2` for Evals,
  Environments, and Models), plus the title, service line, verdict, checked
  manifest (with `rerun_test` extracted from `rerun/test.json` for v2), and
  Markdown report.

  The customer reads their own projects, signed in
  (`Regents.Account.Actors.Human`) or through the agent they paired
  (`Regents.Account.Actors.Agent`, while that pairing is current); another
  person's project, and a withdrawn one, reads as not found.

  The package's bytes are read only by the download read; every other read
  leaves them out. Delivery (`:deliver`) is system-actor only and derives all
  metadata strictly from the verified archive bytes.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  alias Regents.Account.Accounts.HumanAccount
  alias Regents.Techtree.Projects.Project.UnpackPackage

  # What the customer's list shows.
  @listed [:title, :line, :verdict, :delivered_at]
  @package [:title, :package, :package_sha256, :package_size]

  postgres do
    table "projects"
    schema("techtree_app")
    repo(Regents.Repo)

    identity_wheres_to_sql(unique_standing_package: "withdrawn_at IS NULL")

    check_constraints do
      check_constraint(:package, "contents_until_withdrawn",
        check:
          "(withdrawn_at IS NULL) = (package IS NOT NULL AND manifest IS NOT NULL AND report_md IS NOT NULL)",
        message: "standing projects must carry package, manifest, and report"
      )
    end

    custom_indexes do
      index([:delivered_at, :id])
    end
  end

  actions do
    # The customer's projects, newest first.
    read :mine do
      filter expr(is_nil(withdrawn_at))
      prepare build(select: @listed, sort: [delivered_at: :desc, id: :desc])
    end

    # One of the customer's projects, as its page shows it. Primary, with its
    # filter, as field policies need a primary read to run through.
    read :own do
      primary? true
      filter expr(is_nil(withdrawn_at))
    end

    read :own_package do
      filter expr(is_nil(withdrawn_at))
      prepare build(select: @package)
    end

    # Internal system read (e.g. verifying an idempotent OrderBridge retry).
    read :system_by_id do
      get? true
      filter expr(is_nil(withdrawn_at))
    end

    # System-actor delivery from a strictly verified uplift-package/1 or /2 archive.
    create :deliver do
      accept [:human_account_id, :customer_name, :delivered_by_name, :delivered_by_id]

      argument :package_bytes, :binary, allow_nil?: false, sensitive?: true
      argument :expected_sha256, :string, allow_nil?: true

      upsert? true
      upsert_identity :unique_standing_package
      upsert_fields [:delivered_by_name]

      change UnpackPackage
    end
  end

  policies do
    policy action([:deliver, :system_by_id]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    # The customer, signed in or through the agent they paired.
    policy action([:mine, :own, :own_package]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end

    # Their own projects only, so another person's reads as not found.
    policy action([:mine, :own, :own_package]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  field_policies do
    # The package is private, so it is held to its field policy too.
    private_fields :include

    # Its bytes come only through the download read or system delivery,
    # whatever else a read loads or selects.
    field_policy :package do
      authorize_if action([:own_package, :deliver])
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true, constraints: [max_length: 200]

    attribute :line, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:skills, :evals, :environments, :models]]

    attribute :verdict, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [
        one_of: [
          :improved,
          :inconclusive,
          :not_improved,
          :pass_bar_met,
          :pass_bar_not_met,
          :completed,
          :insufficient_tasks
        ]
      ]

    # The checked manifest, the report and the package as uploaded, until the
    # project is withdrawn.
    attribute :manifest, :map, public?: true, sensitive?: true

    attribute :report_md, :string,
      public?: true,
      sensitive?: true,
      constraints: [trim?: false, allow_empty?: true]

    attribute :package, :binary, select_by_default?: false, sensitive?: true
    attribute :package_sha256, :string, allow_nil?: false, public?: true
    attribute :package_size, :integer, allow_nil?: false, public?: true
    # The customer's display name, or their short wallet, when it was delivered.
    attribute :customer_name, :string, allow_nil?: false, public?: true
    create_timestamp :delivered_at, public?: true
    attribute :delivered_by_name, :string, allow_nil?: false, public?: true
    attribute :withdrawn_at, :utc_datetime_usec, public?: true
    attribute :withdrawn_by_name, :string, public?: true
  end

  relationships do
    # The customer.
    belongs_to :human_account, HumanAccount do
      attribute_type :integer
      allow_nil? false
      public? true
    end

    # Nullable for autonomous Uplift Factory deliveries (delivered_by_name stays required).
    belongs_to :delivered_by, HumanAccount do
      attribute_type :integer
      allow_nil? true
    end

    belongs_to :withdrawn_by, HumanAccount, attribute_type: :integer
  end

  identities do
    identity :unique_standing_package, [:human_account_id, :package_sha256],
      where: expr(is_nil(withdrawn_at))
  end
end
