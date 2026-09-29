defmodule RegentPayments.PaymentIntent do
  @moduledoc """
  The terms of one paid action, settled before anyone is asked to pay for it.

  Everything that decides what the money does — the amount, the wallet it
  travels to, and the sentence describing the effect — is written when the
  intent is prepared and never rewritten. Only the status moves after that, so
  a payer signs for exactly what they were shown and `payload_digest` is the
  proof of it.

  Regents never holds the money. The payment goes from the payer's wallet to
  the wallet the terms name; this row records what was promised, and the
  receipt beside it records what happened. Each row belongs to the site that
  prepared it, and a site reads only its own.
  """

  use Ash.Resource,
    otp_app: :regent_payments,
    domain: RegentPayments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Expr

  alias RegentPayments.Types.PaymentIntentStatus
  alias RegentPayments.USDC

  postgres do
    repo &RegentPayments.repo/2
    schema "regent_payments"
    table "payment_intents"
    migrate? false
  end

  attributes do
    uuid_primary_key :id

    # The site that offered these terms, from its own configuration.
    attribute :site, :string, allow_nil?: false, public?: true

    # What the payer's wallet and the facilitator both call this payment. It is
    # the intent's own id in string form, so a signature can be tied back to
    # one row and to no other.
    attribute :payment_identifier, :string, allow_nil?: false, public?: true

    # The offer's kind, which names the site's offer module behind the intent.
    attribute :kind, :atom, allow_nil?: false, public?: true

    # The paying profile. It names a row in the site's identity rather than
    # pointing at one, so a payment record outlives the profile it was made by.
    attribute :actor_profile_id, :uuid, allow_nil?: false, public?: true

    attribute :target_type, :atom, allow_nil?: false, public?: true
    attribute :target_id, :uuid, allow_nil?: false, public?: true

    attribute :amount_atomic, :integer, allow_nil?: false, public?: true
    attribute :asset, :string, allow_nil?: false, public?: true
    attribute :network, :string, allow_nil?: false, public?: true

    # The frozen effect: what is done, at which wallet, and how much. Whatever
    # the kind, the wallet the money goes to is under `pay_to_address`.
    attribute :payload, :map, allow_nil?: false, public?: true

    attribute :payload_digest, :string do
      allow_nil? false
      public? true
      constraints min_length: 64, max_length: 64, match: ~r/\A[0-9a-f]{64}\z/
    end

    attribute :recipient_snapshot, {:array, :map}, allow_nil?: false, public?: true
    attribute :effect_summary, :string, allow_nil?: false, public?: true

    attribute :status, PaymentIntentStatus,
      allow_nil?: false,
      public?: true,
      default: :prepared

    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true

    timestamps()
  end

  identities do
    identity :unique_payment_identifier, [:payment_identifier]
  end

  relationships do
    has_one :receipt, RegentPayments.PaymentReceipt
  end

  preparations do
    prepare RegentPayments.Preparations.ThisSite
  end

  actions do
    defaults [:read]

    read :for_update do
      description "The intent held under a row lock, so it can only be settled once."
      prepare build(lock: :for_update, load: [:receipt])
    end

    read :offered do
      description "The actor's own intents of one kind whose terms still stand, newest first."
      argument :kind, :atom, allow_nil?: false
      filter expr(kind == ^arg(:kind) and expires_at > now())
      prepare build(sort: [inserted_at: :desc])
    end

    create :prepare do
      description "Freezes the terms of one paid action, as the site's offer writes them."
      accept []

      argument :offer, :atom,
        allow_nil?: false,
        description: "The site's offer module, one of those it registers."

      argument :input, :term,
        allow_nil?: false,
        description: "What the offer freezes its terms from."

      # The payer is whoever is signed in, never a value the request carries,
      # so no caller can prepare a payment in somebody else's name.
      change set_attribute(:actor_profile_id, actor(:id))
      change set_attribute(:site, &RegentPayments.site/0)
      change set_attribute(:asset, USDC.asset())
      change set_attribute(:network, USDC.network())
      change RegentPayments.Changes.FreezeTerms
    end

    update :mark_payment_required do
      description "The payer has been handed the terms and asked to sign for them."
      accept []
      change set_attribute(:status, :payment_required)
    end

    update :mark_settlement_pending do
      description "The settlement attempt is committed; its outcome has not been recorded yet."
      accept []
      change set_attribute(:status, :settlement_pending)
    end

    update :mark_settled do
      description "The money has moved."
      accept []
      change set_attribute(:status, :settled)
    end

    update :mark_applied do
      description "The effect the payer paid for has been carried out."
      accept []
      change set_attribute(:status, :applied)
    end

    update :mark_failed do
      description "The facilitator refused to settle this payment."
      accept []
      change set_attribute(:status, :failed)
    end

    update :expire do
      description "The terms stood too long unpaid to still be honoured."
      accept []
      change set_attribute(:status, :expired)
    end
  end

  policies do
    policy action(:prepare) do
      authorize_if RegentPayments.Checks.OfferTakesPayer
    end

    # Keep payer ownership at the domain boundary, including row-lock reads.
    policy action_type(:read) do
      authorize_if expr(actor_profile_id == ^actor(:id))
    end

    # Every status change is the library's own step (`RegentPayments.Steps`),
    # made for the intent's payer; a site cannot move an intent on itself.
    policy action_type(:update) do
      forbid_unless context_equals(:regent_payments, :purchase)
      authorize_if expr(actor_profile_id == ^actor(:id))
    end
  end
end
