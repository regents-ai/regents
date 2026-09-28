defmodule RegentPayments do
  @moduledoc """
  Paid actions for every Regent site, in USDC on Base.

  Regents holds no money. There is no balance, top-up, credit or withdrawal
  here, and no refund: a payment intent freezes what an action will cost and
  which wallet receives the money, the payer's own wallet then pays that
  wallet directly through an x402 facilitator, and the receipt records what
  happened. The person's USDC Balance is always read live from their own
  wallet on Base (`RegentPayments.Balance`).

  Each site registers the actions it sells as `RegentPayments.Offer` modules,
  names itself, and supplies its repository:

      config :regent_payments,
        repo: MySite.Repo,
        site: "mysite",
        offers: [MySite.Payments.Tip],
        base_rpc_url: System.get_env("BASE_RPC_URL"),
        payment_chain: %{name: "Base", rpc_url: "https://mainnet.base.org"},
        wallet_proof: [name: "MySite", version: "1", endpoint: MySiteWeb.Endpoint]

      config :regent_payments, RegentPayments.Facilitator,
        url: X402.Facilitator.Auth.CDP.facilitator_url(),
        auth: {X402.Facilitator.Auth.CDP, api_key_id: id, api_key_secret: secret}

  and starts `RegentPayments.Supervisor` beside its repository. Paying goes
  through `RegentPayments.Purchase` (x402, for agents) and
  `RegentPayments.WalletPayment` (a page's signed-in wallet). The schema is
  migrated once, from Regents, with `RegentPayments.Migrator`.
  """

  use Ash.Domain, otp_app: :regent_payments

  import Ash.Expr, only: [expr: 1]

  alias RegentPayments.PaymentReceipt

  resources do
    resource RegentPayments.PaymentIntent do
      define :prepare_payment_intent, action: :prepare, args: [:offer, :input]
      define :get_payment_intent, action: :read, get_by: [:id]
      define :lock_payment_intent, action: :for_update, get_by: [:id]
      define :offered_payment_intents, action: :offered, args: [:kind]
      define :mark_payment_required, action: :mark_payment_required
      define :mark_settlement_pending, action: :mark_settlement_pending
      define :mark_settled, action: :mark_settled
      define :mark_applied, action: :mark_applied
      define :mark_payment_failed, action: :mark_failed
      define :expire_payment_intent, action: :expire
    end

    resource RegentPayments.PaymentReceipt do
      define :record_payment_receipt, action: :record
    end
  end

  @doc false
  def repo(_resource, _operation), do: Application.fetch_env!(:regent_payments, :repo)

  @doc "The name this site's payments are written under."
  @spec site() :: String.t()
  def site, do: Application.fetch_env!(:regent_payments, :site)

  @doc """
  A profile's whole record of settled payments of one `kind`, both ways: how
  many it has made and what they came to, and how many were made to it and
  what those came to, all in USDC's atomic units.

  A wallet paying another wallet directly carries nothing on chain that says
  which profile sent it. The intent behind each settled receipt does: it names
  the paying profile and the target at the moment the terms were frozen.

  Four filtered aggregates, all carried by one statement.
  """
  @spec settled_record(atom(), Ash.UUID.t()) :: {:ok, map()} | {:error, Ash.Error.t()}
  def settled_record(kind, profile_id) do
    aggregates = [
      {:given_count, :count,
       query: [filter: expr(payment_intent.actor_profile_id == ^profile_id)]},
      {:given_atomic, :sum,
       field: :amount_atomic,
       query: [filter: expr(payment_intent.actor_profile_id == ^profile_id)]},
      {:received_count, :count, query: [filter: expr(payment_intent.target_id == ^profile_id)]},
      {:received_atomic, :sum,
       field: :amount_atomic, query: [filter: expr(payment_intent.target_id == ^profile_id)]}
    ]

    query = settled(:settled_by_party, %{kind: kind, profile_id: profile_id})

    with {:ok, counted} <- Ash.aggregate(query, aggregates) do
      {:ok,
       %{
         given_count: counted.given_count || 0,
         given_atomic: counted.given_atomic || 0,
         received_count: counted.received_count || 0,
         received_atomic: counted.received_atomic || 0
       }}
    end
  end

  @doc """
  What each of the given targets has been paid in settled payments of one
  `kind`, keyed by target id and leaving out those paid nothing: one filtered
  sum per target, all carried by the same statement.
  """
  @spec settled_by_target(atom(), [Ash.UUID.t()]) ::
          {:ok, %{Ash.UUID.t() => pos_integer()}} | {:error, Ash.Error.t()}
  def settled_by_target(_kind, []), do: {:ok, %{}}

  # The atoms are paid_0, paid_1, … by position, so every call reuses the same
  # few names; nothing a caller sends becomes an atom.
  def settled_by_target(kind, target_ids) do
    named = Enum.with_index(target_ids, fn target_id, index -> {:"paid_#{index}", target_id} end)

    sums =
      Enum.map(named, fn {name, target_id} ->
        {name, :sum,
         field: :amount_atomic, query: [filter: expr(payment_intent.target_id == ^target_id)]}
      end)

    query = settled(:settled_for_targets, %{kind: kind, target_ids: target_ids})

    with {:ok, paid} <- Ash.aggregate(query, sums) do
      positive =
        for {name, target_id} <- named,
            is_integer(paid[name]) and paid[name] > 0,
            into: %{} do
          {target_id, paid[name]}
        end

      {:ok, positive}
    end
  end

  # The totals a public page shows are public numbers. The receipts they are
  # counted from stay behind their payer, which is the one reason
  # authorization is set aside here: nothing but the totals leaves this query.
  defp settled(action, arguments),
    do: Ash.Query.for_read(PaymentReceipt, action, arguments, authorize?: false)
end
