defmodule Regents.Techtree.Factory.Order do
  @moduledoc """
  One Uplift Factory job order in `techtree_app.job_orders`.

  A customer (signed-in human or paired SIWA agent) requests work in one of the
  four lanes (`:skills`, `:evals`, `:environments`, `:models`) with a bounded
  material archive (`<= 5 MiB` `.tar.gz`) and optional `Runbook` policy.

  State transitions are enforced by `AshStateMachine`:
  - `requested` -> `checking` -> `quoted` -> `paid` | `expired`
  - `requested` | `checking` -> `refused`
  - `requested` | `checking` | `quoted` -> `cancelled`
  - `paid` -> `running` (claimed atomically by `OrderBridge`) -> `delivered` | `failed`

  Only the ordering customer (human or paired agent) reads or cancels their own
  order; only the system actor (via constant-time operator Bearer token on
  `/api/v1/techtree/factory/orders*`) lists paid orders, claims material bytes,
  or delivers a verified `uplift-package/1` or `uplift-package/2` project.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.Factory,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine],
    primary_read_warning?: false

  alias Regents.Account.Accounts.HumanAccount
  alias Regents.Techtree.Factory.Order.{DeliverPackage, PrepareRequest}
  alias Regents.Techtree.Factory.Runbook
  alias Regents.Techtree.Projects.Project

  @quote_fields "quote_amount, quote_scope, quote_expires_at, payment_reference"

  @public_fields [
    :id,
    :lane,
    :title,
    :success,
    :project_name,
    :state,
    :quote_amount,
    :quote_scope,
    :quote_expires_at,
    :payment_reference,
    :customer_company,
    :customer_contact_name,
    :customer_contact_email,
    :agent_wallet,
    :runbook,
    :material_sha256,
    :material_size,
    :requested_at,
    :checking_at,
    :quoted_at,
    :paid_at,
    :claimed_at,
    :delivered_at,
    :refused_at,
    :expired_at,
    :cancelled_at,
    :external_job_id,
    :human_account_id,
    :delivered_project_id
  ]

  postgres do
    table "job_orders"
    schema("techtree_app")
    repo(Regents.Repo)

    migration_defaults(runbook: "fragment(\"'{}'::jsonb\")")

    check_constraints do
      check_constraint(:quote_amount, "quote_whole",
        check:
          "num_nulls(#{@quote_fields}) = 4 OR (num_nulls(#{@quote_fields}) = 0 AND quote_amount > 0)",
        message: "is set whole or not at all"
      )
    end

    custom_indexes do
      index([:quote_expires_at], where: "state = 'quoted'")
      index([:state, :paid_at], where: "state = 'paid'")
    end
  end

  state_machine do
    initial_states([:requested])
    default_initial_state(:requested)
    extra_states([:awaiting_decision])

    transitions do
      transition(:check, from: :requested, to: :checking)
      transition(:set_quote, from: [:requested, :checking], to: :quoted)
      transition(:refuse, from: [:requested, :checking], to: :refused)
      transition(:cancel, from: [:requested, :checking, :quoted], to: :cancelled)
      transition(:mark_paid, from: :quoted, to: :paid)
      transition(:expire, from: :quoted, to: :expired)
      transition(:claim, from: :paid, to: :running)
      transition(:deliver, from: [:paid, :running, :awaiting_decision], to: :delivered)
      transition(:fail, from: [:paid, :running, :awaiting_decision], to: :failed)
    end
  end

  actions do
    create :request do
      accept [
        :lane,
        :title,
        :success,
        :project_name,
        :customer_company,
        :customer_contact_name,
        :customer_contact_email,
        :runbook
      ]

      argument :material_archive_base64, :string, allow_nil?: true, sensitive?: true

      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      change PrepareRequest
    end

    read :mine do
      prepare build(select: @public_fields, sort: [requested_at: :desc, id: :desc])
    end

    read :own do
      primary? true
      prepare build(select: @public_fields)
    end

    read :bridge_list do
      argument :state, :atom,
        allow_nil?: false,
        default: :paid,
        constraints: [
          one_of: [
            :requested,
            :checking,
            :quoted,
            :paid,
            :running,
            :awaiting_decision,
            :delivered,
            :failed,
            :refused,
            :expired,
            :cancelled
          ]
        ]

      filter expr(
               state == ^arg(:state) and
                 (^arg(:state) != :paid or not is_nil(material_sha256))
             )

      prepare build(select: @public_fields, sort: [paid_at: :asc, requested_at: :asc])
    end

    read :bridge_get do
      get? true
      prepare build(select: @public_fields)
    end

    read :bridge_materials do
      get? true
      prepare build(select: [:id, :state, :material_archive, :material_sha256])
    end

    update :check do
      accept []
      change transition_state(:checking)
      change set_attribute(:checking_at, &DateTime.utc_now/0)
    end

    update :set_quote do
      accept [:quote_amount, :quote_scope, :quote_expires_at, :payment_reference]
      require_attributes [:quote_amount, :quote_scope, :quote_expires_at, :payment_reference]

      validate numericality(:quote_amount, greater_than: 0)
      change transition_state(:quoted)
      change set_attribute(:quoted_at, &DateTime.utc_now/0)
    end

    update :mark_paid do
      accept []
      change transition_state(:paid)
      change set_attribute(:paid_at, &DateTime.utc_now/0)
    end

    update :expire do
      accept []
      change transition_state(:expired)
      change set_attribute(:expired_at, &DateTime.utc_now/0)
    end

    update :refuse do
      accept []
      change transition_state(:refused)
      change set_attribute(:refused_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      require_atomic? false

      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      change transition_state(:cancelled)
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)
    end

    # Atomically transitions a paid order with materials to :running in a single
    # SQL UPDATE so concurrent POST /claim calls cannot both succeed.
    update :claim do
      accept []

      validate present(:material_sha256), message: "material archive is required before claiming"
      change transition_state(:running)
      change atomic_update(:claimed_at, expr(now()))
    end

    # Atomically verifies and persists the delivered uplift-package Project and marks :delivered.
    update :deliver do
      accept []
      require_atomic? false

      argument :package_bytes, :binary, allow_nil?: false, sensitive?: true
      argument :expected_sha256, :string, allow_nil?: false
      argument :external_job_id, :string, allow_nil?: false, constraints: [max_length: 120]

      change transition_state(:delivered)
      change DeliverPackage
    end

    update :fail do
      accept []
      change transition_state(:failed)
    end
  end

  policies do
    policy action([
             :bridge_list,
             :bridge_get,
             :bridge_materials,
             :check,
             :set_quote,
             :mark_paid,
             :expire,
             :refuse,
             :claim,
             :deliver,
             :fail
           ]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action(:request) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end

    policy action([:mine, :own, :cancel]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end

    policy action([:mine, :own, :cancel]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  field_policies do
    private_fields :include

    field_policy :material_archive do
      authorize_if actor_attribute_equals(:role, :system)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :lane, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:skills, :evals, :environments, :models]]

    attribute :title, :string, allow_nil?: false, public?: true, constraints: [max_length: 200]
    attribute :success, :string, allow_nil?: false, public?: true, constraints: [max_length: 2000]
    attribute :project_name, :string, public?: true, constraints: [max_length: 63]

    attribute :quote_amount, :integer, public?: true
    attribute :quote_scope, :string, public?: true, constraints: [max_length: 1000]
    attribute :quote_expires_at, :utc_datetime_usec, public?: true
    attribute :payment_reference, :string, public?: true, constraints: [max_length: 120]

    attribute :customer_company, :string, public?: true, constraints: [max_length: 200]
    attribute :customer_contact_name, :string, public?: true, constraints: [max_length: 200]
    attribute :customer_contact_email, :string, public?: true, constraints: [max_length: 320]
    attribute :agent_wallet, :string, public?: true, constraints: [max_length: 64]

    attribute :runbook, Runbook, allow_nil?: false, default: %{}, public?: true

    attribute :material_archive, :binary, select_by_default?: false, sensitive?: true
    attribute :material_sha256, :string, public?: true, constraints: [max_length: 64]
    attribute :material_size, :integer, public?: true

    create_timestamp :requested_at, public?: true
    attribute :checking_at, :utc_datetime_usec, public?: true
    attribute :quoted_at, :utc_datetime_usec, public?: true
    attribute :paid_at, :utc_datetime_usec, public?: true
    attribute :claimed_at, :utc_datetime_usec, public?: true
    attribute :delivered_at, :utc_datetime_usec, public?: true
    attribute :refused_at, :utc_datetime_usec, public?: true
    attribute :expired_at, :utc_datetime_usec, public?: true
    attribute :cancelled_at, :utc_datetime_usec, public?: true

    attribute :external_job_id, :string, public?: true, constraints: [max_length: 120]

    # Retained nullable for backwards compatibility with legacy techtree.sh rows.
    attribute :agent_id, :uuid, allow_nil?: true, public?: true
  end

  relationships do
    belongs_to :human_account, HumanAccount do
      attribute_type :integer
      allow_nil? true
      public? true
    end

    belongs_to :delivered_project, Project do
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_payment_reference, [:payment_reference]
  end

  @doc "Maps plural Techtree lane atoms to singular `OrderBridge` kind strings."
  @spec bridge_kind(atom()) :: String.t()
  def bridge_kind(:skills), do: "skill"
  def bridge_kind(:evals), do: "eval"
  def bridge_kind(:environments), do: "environment"
  def bridge_kind(:models), do: "model"

  @doc "Converts USDC millionths (`quote_amount`) to positive integer cents for `OrderBridge`."
  @spec quote_cents(integer() | nil) :: pos_integer()
  def quote_cents(amount) when is_integer(amount) and amount > 0,
    do: max(div(amount, 10_000), 1)

  def quote_cents(_other), do: 500
end
