defmodule Regents.Autolaunch.Subject do
  @moduledoc """
  One launched subject: its token and the contracts its revenue moves through,
  with the protocol's share and the totals read from them.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # A subject id occupies one public URL segment, the identifier format the
  # public route catalog accepts.
  @subject_id_shape ~r/\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z/

  postgres do
    table "subjects"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id, public?: false

    attribute :subject_id, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 128, trim?: false, match: @subject_id_shape
    end

    attribute :subject_kind, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :chain_id, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :token_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :splitter_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :ingress_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :treasury_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    # The canonical zero-referral receiver this launch graduated with. Only
    # 490.8.2/.3 projection may fill it, so it stays null until then and every
    # payment action refuses while it is absent.
    attribute :canonical_receiver_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :factory_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :revenue_router_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :creator_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :staker_pool_bps, :integer do
      public? true
      constraints min: 0, max: 10_000
    end

    attribute :protocol_skim_bps_snapshot, :integer do
      public? true
      constraints min: 0, max: 10_000
    end

    attribute :current_protocol_skim_bps, :integer do
      public? true
      constraints min: 0, max: 10_000
    end

    attribute :protocol_fee_usdc_total_raw, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :regent_emission_total_raw, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :pending_buyback_usdc_raw, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    timestamps()
  end

  relationships do
    has_many :payment_links, Regents.Autolaunch.PaymentLink

    belongs_to :treasury_security_report,
               Regents.Autolaunch.TreasurySecurityReport do
      attribute_public? true
    end
  end

  identities do
    identity :unique_subject_id, [:subject_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
