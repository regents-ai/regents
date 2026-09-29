defmodule RegentPayments.Offer do
  @moduledoc """
  One paid action a site sells, and the seam between the payment and the thing
  paid for.

  The library owns the payment: the frozen terms, the x402 settlement, the
  receipt and the status of each intent. The site owns what the money buys: a
  tip reaching a profile, a report being published, a run being opened. A
  site writes one module per paid action implementing this behaviour and
  lists it in its configuration:

      config :regent_payments, offers: [MySite.Payments.Tip, MySite.Payments.Fix]

  The library never names a site module. It finds the offer behind an intent
  by the intent's `kind`, which is the offer's `c:kind/0`.

  Every offer is paid to the wallet its terms name. The payer's wallet pays
  that wallet directly; Regents never holds the money.
  """

  @typedoc """
  The terms of one payment, frozen when the intent is prepared and never
  rewritten: how much, which wallet receives it, what the money is for
  (`target_id`), the offer's own record of the effect (`payload`, which the
  library completes with `pay_to_address` and `amount_atomic`), who is paid,
  and the sentence the payer is shown.
  """
  @type terms :: %{
          required(:amount_atomic) => pos_integer(),
          required(:pay_to_address) => String.t(),
          required(:target_id) => Ash.UUID.t(),
          required(:payload) => %{String.t() => term()},
          required(:recipient_snapshot) => [map()],
          required(:effect_summary) => String.t()
        }

  @doc "The kind of payment this offer makes, as the intent records it. Unique per site."
  @callback kind() :: atom()

  @doc "The kind of thing a payment of this offer is for, as the intent records it."
  @callback target_type() :: atom()

  @doc """
  Whether `actor` may pay for this offer and read its intents back. Called at
  preparation and on every read; the library has already checked that an
  actor is present.
  """
  @callback payer?(actor :: struct()) :: boolean()

  @doc """
  Freezes the terms for `input` prepared by `actor`, or refuses them with the
  reasons, as Ash errors naming the field the caller sent.
  """
  @callback freeze(input :: term(), actor :: struct()) ::
              {:ok, terms()} | {:error, Exception.t() | [Exception.t()]}

  @doc """
  Carries out what a settled payment bought. `:complete` marks the intent
  applied; `:incomplete` or an error leaves it settled, with its receipt, for
  the site to finish. `context` is what the site's door passed to
  `RegentPayments.Purchase.execute/3`.

  It is called inside the database transaction that holds the intent's row
  lock (`SELECT ... FOR UPDATE` on the payment intent) and marks the intent
  applied. It writes the site's own record of the effect, such as the run a
  payment opened, through the same repository the library is configured
  with, so that write joins the open transaction: the site's row and the
  applied mark are saved together or not at all. `{:error, reason}` rolls
  both back and leaves the intent settled. `:incomplete` commits what was
  written and leaves the intent settled.

  The site's row must be unique per intent id in the database, for example
  with a unique index on the column holding the intent's id, so no path can
  ever save two effects for one payment.

  Anything outside the database, such as starting a job or a runner, waits
  until the transaction has committed: insert an Oban job in the same
  transaction, or start it after `RegentPayments.Purchase.execute/3`
  returns. An Ash `after_transaction` hook on the site's write does not
  wait, because inside this open transaction it runs before the commit.
  Nothing outside the database starts from inside `carry_out/4` itself.
  """
  @callback carry_out(
              intent :: RegentPayments.PaymentIntent.t(),
              receipt :: RegentPayments.PaymentReceipt.t(),
              actor :: struct(),
              context :: map()
            ) :: {:ok, :complete | :incomplete} | {:error, term()}

  @doc """
  Whether a settled intent whose effect is not complete is carried out again
  on the payer's next execute. An offer whose effect must not be repeated
  answers `false` and finishes it by its own means.

  A resumed carry out runs under the same row lock and in the same kind of
  transaction as the first, and an applied intent is never carried out
  again. The site's effect row must still be unique per intent id in the
  database, so an `:incomplete` effect that is resumed finishes the row it
  started rather than writing a second one.
  """
  @callback resumes?() :: boolean()

  @doc "The offer registered for `module`, if the site lists it."
  @spec registered(term()) :: {:ok, module()} | :error
  def registered(module) do
    if module in offers(), do: {:ok, module}, else: :error
  end

  @doc "The registered offer whose kind is `kind`."
  @spec for_kind!(atom()) :: module()
  def for_kind!(kind) do
    Enum.find(offers(), &(&1.kind() == kind)) ||
      raise ArgumentError, "no offer is registered for the kind #{inspect(kind)}"
  end

  @doc """
  `:ok` when `amount_atomic` lies between `min` and `max` inclusive, or the
  refusal naming the range in USDC.
  """
  @spec amount_between(integer(), pos_integer(), pos_integer()) :: :ok | {:error, Exception.t()}
  def amount_between(amount_atomic, min, max) when amount_atomic >= min and amount_atomic <= max,
    do: :ok

  def amount_between(amount_atomic, min, max) do
    {:error,
     Ash.Error.Changes.InvalidAttribute.exception(
       field: :amount_atomic,
       value: amount_atomic,
       message:
         "must be between #{RegentPayments.USDC.format(min)} and #{RegentPayments.USDC.format(max)} USDC"
     )}
  end

  defp offers, do: Application.fetch_env!(:regent_payments, :offers)
end
