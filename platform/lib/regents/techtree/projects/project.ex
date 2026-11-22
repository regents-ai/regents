defmodule Regents.Techtree.Projects.Project do
  @moduledoc """
  One project Techtree's team delivered to a customer's account: the package
  the work produced, kept whole, and what its pages show, read out of it once:
  the title, the service line, the verdict, the manifest and the report. The
  customer's name, and the name of the admin who delivered it and when, are
  kept as they were then.

  The customer reads their own projects, signed in
  (`Regents.Account.Actors.Human`) or through the agent they paired
  (`Regents.Account.Actors.Agent`, while that pairing is current); another
  person's project, and a withdrawn one, reads as not found.

  The package's bytes are read only by the download read; every other read
  leaves them out.

  Read only here: techtree.sh's team delivers and withdraws projects, and its
  migration made the table.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Account.Accounts.HumanAccount

  # What the customer's list shows.
  @listed [:title, :line, :verdict, :delivered_at]
  @package [:title, :package, :package_sha256, :package_size]

  # Techtree's own area of the shared database, where techtree.sh's team writes
  # these rows; their migration stays techtree.sh's.
  postgres do
    table "projects"
    schema("techtree_app")
    repo(Regents.Repo)
    migrate?(false)
  end

  actions do
    # The customer's projects, newest first.
    read :mine do
      filter expr(is_nil(withdrawn_at))
      prepare build(select: @listed, sort: [delivered_at: :desc, id: :desc])
    end

    # One of the customer's projects, as its page shows it.
    read :own do
      filter expr(is_nil(withdrawn_at))
    end

    read :own_package do
      filter expr(is_nil(withdrawn_at))
      prepare build(select: @package)
    end
  end

  policies do
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

    belongs_to :delivered_by, HumanAccount do
      attribute_type :integer
      allow_nil? false
    end

    belongs_to :withdrawn_by, HumanAccount, attribute_type: :integer
  end
end
