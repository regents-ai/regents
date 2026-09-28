defmodule RegentPayments.Purchase do
  @moduledoc """
  One way to buy a paid action, whichever door the buyer came through: a
  site's HTTP payment endpoints, its wallet-signed agent endpoints and its
  hosted MCP tools all run this, and a page paying with its signed-in wallet
  runs it through `RegentPayments.WalletPayment`.

  Preparing an action freezes what it will cost and who receives the money.
  Executing it hands back the x402 terms to sign, and then, once a signed
  payment arrives, checks that payment against those same frozen terms before
  any money moves. Nothing the caller sends can change the amount or the
  destination after the fact: the terms are read from the stored intent every
  time, never from the request. The intent is settled at most once, and
  reading it back never pays.

  The money never passes through Regents. The payer's wallet pays the wallet
  the terms name, the facilitator verifies and settles it, and what is stored
  is the record of what was promised and what happened. What the money bought
  is then carried out by the site's offer (`c:RegentPayments.Offer.carry_out/4`).

  A short row lock commits the settlement attempt before the facilitator is
  asked. A crash leaves the intent marked `settlement_pending` for a person to
  reconcile, never an automatic second payment. The receipt commits before the
  offer carries anything out, so a later failure cannot erase it. What the
  money bought is carried out under the intent's row lock and marked applied
  in the same transaction, so it runs once per payment across every machine.
  """

  require Logger

  alias RegentPayments.Offer
  alias RegentPayments.PaymentIntent
  alias RegentPayments.PaymentReceipt
  alias RegentPayments.USDC
  alias X402.Extensions.PaymentIdentifier
  alias X402.Facilitator
  alias X402.PaymentSignature
  alias X402.Scheme.ExactEVM

  @facilitator RegentPayments.Facilitator

  # How long the facilitator may take to settle a signed payment. It is
  # advertised in the terms, so a wallet knows what window it is signing for.
  @max_timeout_seconds 300

  @typedoc """
  What an execute carries besides the intent's id: the signed payment, if the
  payer has signed (the x402 payment as a map, or the encoded
  `payment-signature` header); the wallet the payment must have been signed
  by, when the door knows nothing else about the caller; and whatever the
  site's offer needs to carry the payment out, such as the browser it was
  bought from.
  """
  @type request :: %{
          payment: map() | String.t() | nil,
          payer: String.t() | nil,
          context: map()
        }

  @typedoc "Where a payment intent stands after an execute, for the door to answer."
  @type answer ::
          {:payment_required, PaymentIntent.t()}
          | {:payment_rejected, PaymentIntent.t(), String.t()}
          | {:applied, PaymentIntent.t(), PaymentReceipt.t()}
          | {:settled, PaymentIntent.t(), PaymentReceipt.t()}
          | {:settlement_pending, PaymentIntent.t()}
          | {:expired, PaymentIntent.t()}
          | {:facilitator_unavailable, PaymentIntent.t(), String.t()}
          | {:error, term()}

  # Preparing a payment

  @doc "Freezes the terms of `offer` for `input`, paid by `actor`."
  @spec prepare(module(), term(), struct()) :: {:ok, PaymentIntent.t()} | {:error, term()}
  def prepare(offer, input, actor) do
    RegentPayments.prepare_payment_intent(offer, input, actor: actor)
  end

  @doc """
  The terms of `offer` already on offer to `actor` that `same?` recognises,
  newest first, while they still stand; `nil` when there are none. A door
  that is asked again after a timeout answers with the purchase it started.
  """
  @spec on_offer(module(), struct(), (PaymentIntent.t() -> boolean())) :: PaymentIntent.t() | nil
  def on_offer(offer, actor, same?) do
    offer.kind()
    |> RegentPayments.offered_payment_intents!(actor: actor)
    |> Enum.find(same?)
  end

  # Executing a payment intent

  @doc """
  Moves `actor`'s intent `id` one step on: offers the terms when no payment
  came, or checks the payment against them, settles it once, and carries out
  what it bought. Only the caller that commits the pending transition asks
  the facilitator to settle, after the transaction has committed.
  """
  @spec execute(struct(), String.t(), request()) :: answer()
  def execute(actor, id, request) do
    case Ash.transact([PaymentIntent, PaymentReceipt], fn -> attempt(actor, id, request) end) do
      {:ok, {:settled, {:dispatch, found, payment, requirement, request}}} ->
        settle(actor, found, payment, requirement, request)

      {:ok, {:settled, {:carry_out, found}}} ->
        carried_out(actor, found.id, request)

      {:ok, {:settled, answer}} ->
        answer

      {:error, failed_write} ->
        {:error, failed_write}
    end
  end

  # A refusal is an answer, and the status it wrote down travels out with it.
  # Only a write that genuinely failed undoes the transaction.
  defp attempt(actor, id, request) do
    case locked(actor, id, request) do
      {:error, failure} when is_exception(failure) -> {:error, failure}
      answer -> {:settled, answer}
    end
  end

  defp locked(actor, id, request) do
    case intent(actor, id, &RegentPayments.lock_payment_intent/2) do
      {:ok, found} -> advance(actor, found, request)
      {:error, failure} -> {:error, failure}
    end
  end

  defp advance(_actor, %{status: :applied} = found, _request),
    do: {:applied, found, found.receipt}

  # A settled intent whose effect is incomplete is carried out again on the
  # next call when its offer allows it: from the same frozen terms, once this
  # read's transaction has ended, under the row lock `carried_out/3` takes.
  defp advance(_actor, %{status: :settled} = found, _request) do
    if Offer.for_kind!(found.kind).resumes?(),
      do: {:carry_out, found},
      else: {:settled, found, found.receipt}
  end

  defp advance(_actor, %{status: :settlement_pending} = found, _request) do
    {:settlement_pending, found}
  end

  defp advance(actor, found, request) do
    if DateTime.before?(found.expires_at, DateTime.utc_now()) do
      expire(actor, found)
    else
      offer_or_settle(actor, found, request)
    end
  end

  defp expire(actor, found) do
    case RegentPayments.expire_payment_intent(found, actor: actor) do
      {:ok, expired} -> {:expired, expired}
      {:error, failure} -> {:error, failure}
    end
  end

  defp offer_or_settle(actor, found, %{payment: nil}) do
    case RegentPayments.mark_payment_required(found, actor: actor) do
      {:ok, waiting} -> {:payment_required, waiting}
      {:error, failure} -> {:error, failure}
    end
  end

  defp offer_or_settle(actor, found, request) do
    requirement = requirement(found)

    case checked_payment(request, found, requirement) do
      {:ok, payment} ->
        with {:ok, pending} <- RegentPayments.mark_settlement_pending(found, actor: actor) do
          {:dispatch, pending, payment, requirement, request}
        end

      {:refused, reason} ->
        {:payment_rejected, found, reason}

      {:unavailable, reason} ->
        {:facilitator_unavailable, found, reason}
    end
  end

  # Checking a payment against the frozen terms

  defp checked_payment(request, found, requirement) do
    with {:ok, payment} <- decoded(request.payment, requirement),
         :ok <- signed_by(payment, request.payer),
         :ok <- names_this_intent(payment, found),
         :ok <- prechecked(payment, requirement),
         :ok <- verified(payment, requirement) do
      {:ok, payment}
    end
  end

  # Decoding matches the signed `accepted` terms against this intent's own
  # requirement field for field, so a signature made for any other amount,
  # asset, network or wallet is refused before anything else happens.
  defp decoded(payment, requirement) when is_binary(payment) do
    payment |> PaymentSignature.decode_and_validate(requirement) |> decoded()
  end

  defp decoded(payment, requirement) when is_map(payment) do
    payment |> PaymentSignature.validate(requirement) |> decoded()
  end

  defp decoded({:ok, payment}), do: {:ok, payment}

  defp decoded({:error, :no_matching_requirements}),
    do: {:refused, "That payment was signed for different terms than this payment intent's."}

  defp decoded({:error, _reason}),
    do: {:refused, "That payment signature could not be read as an x402 version 2 payment."}

  # A door that knows the buyer only by the wallet it named is held to a
  # payment from that wallet, so nobody buys in another wallet's name.
  defp signed_by(_payment, nil), do: :ok

  defp signed_by(payment, payer) do
    from = get_in(payment, ["payload", "authorization", "from"])

    if is_binary(from) and String.downcase(from) == payer,
      do: :ok,
      else: {:refused, "That payment was signed by a different wallet than wallet_address names."}
  end

  defp names_this_intent(payment, found) do
    case echoed_identifier(payment) do
      :absent -> :ok
      {:ok, identifier} -> matching_identifier(identifier, found.payment_identifier)
      :error -> {:refused, "The payment identifier in that signature could not be read."}
    end
  end

  defp matching_identifier(identifier, identifier), do: :ok

  defp matching_identifier(_identifier, _expected),
    do: {:refused, "That payment signature names a different payment."}

  defp echoed_identifier(payment) do
    case get_in(payment, ["extensions", "paymentIdentifier"]) do
      nil -> :absent
      encoded when is_binary(encoded) -> decoded_identifier(encoded)
      _other -> :error
    end
  end

  defp decoded_identifier(encoded) do
    case PaymentIdentifier.decode(encoded) do
      {:ok, identifier} -> {:ok, identifier}
      {:error, _reason} -> :error
    end
  end

  # The local check of the signed authorization: the wallet it pays, the exact
  # amount, and the window it is valid for.
  defp prechecked(payment, requirement) do
    case ExactEVM.precheck(payment, requirement, []) do
      :ok -> :ok
      {:error, {:precheck_failed, reason}} -> {:refused, precheck_message(reason)}
    end
  end

  defp precheck_message(:pay_to_mismatch),
    do: "That payment pays a different wallet than these terms."

  defp precheck_message(:amount_mismatch),
    do: "That payment is for a different amount than these terms."

  defp precheck_message(:authorization_expired),
    do: "That payment authorization has already expired."

  defp precheck_message(:authorization_not_yet_valid),
    do: "That payment authorization is not valid yet."

  defp precheck_message(_reason), do: "That payment authorization could not be read."

  defp verified(payment, requirement) do
    case Facilitator.verify(@facilitator, payment, requirement) do
      {:ok, %{status: status, body: %{"isValid" => true}}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: %{"isValid" => false} = body}} when status in 200..299 ->
        {:refused, invalid_message(body)}

      _unclear ->
        {:unavailable, "The payment service could not be reached before a settlement result."}
    end
  end

  defp invalid_message(%{"invalidReason" => reason}) when is_binary(reason) do
    "The payment service would not accept that payment: #{reason}."
  end

  defp invalid_message(_body), do: "The payment service would not accept that payment."

  # Settling

  defp settle(actor, found, payment, requirement, request) do
    case Facilitator.settle(@facilitator, payment, requirement) do
      {:ok, %{status: status, body: %{"success" => true} = body}} when status in 200..299 ->
        apply_payment(actor, found, payment, body, request)

      {:ok, %{status: status, body: %{"success" => false} = body}} when status in 200..299 ->
        refused_settlement(actor, found, body)

      _unclear ->
        hold(actor, found)
    end
  end

  # A facilitator that has not finished settling may still move the money, so
  # nothing here retries or refuses it. A person reconciles it by hand.
  defp refused_settlement(actor, found, %{"errorReason" => "settlement_pending"}) do
    hold(actor, found)
  end

  defp refused_settlement(actor, found, body) do
    case RegentPayments.mark_payment_failed(found, actor: actor) do
      {:ok, failed} -> {:payment_rejected, failed, settlement_message(body)}
      {:error, failure} -> {:error, failure}
    end
  end

  defp settlement_message(%{"errorReason" => reason}) when is_binary(reason) do
    "The payment service could not settle that payment: #{reason}."
  end

  defp settlement_message(_body), do: "The payment service could not settle that payment."

  defp hold(actor, found) do
    case RegentPayments.mark_settlement_pending(found, actor: actor) do
      {:ok, pending} -> {:settlement_pending, pending}
      {:error, failure} -> {:error, failure}
    end
  end

  defp apply_payment(actor, found, payment, body, request) do
    persisted =
      Ash.transact([PaymentIntent, PaymentReceipt], fn ->
        with {:ok, receipt} <- record_receipt(actor, found, payment, body),
             {:ok, settled} <- RegentPayments.mark_settled(found, actor: actor) do
          {settled, receipt}
        end
      end)

    case persisted do
      {:ok, _settled} -> carried_out(actor, found.id, request)
      # The already-committed pending marker survives. Never redispatch.
      {:error, _failed_write} -> {:settlement_pending, found}
    end
  end

  # The effect is carried out in one transaction on the site's repository. It
  # first takes the intent's row lock in the database (SELECT ... FOR UPDATE),
  # so any other caller, on this machine or another, waits on that row and
  # then finds the intent applied. What the offer writes and the applied mark
  # commit together or not at all; after a rollback the intent is answered as
  # it stands, settled with its receipt.
  defp carried_out(actor, id, request) do
    locked_carry_out = fn ->
      with {:ok, locked} <- RegentPayments.lock_payment_intent(id, actor: actor) do
        carry_out_once(actor, locked, request)
      end
    end

    case Ash.transact([PaymentIntent, PaymentReceipt], locked_carry_out) do
      {:ok, answer} -> answer
      {:error, failure} -> as_it_stands(actor, id, failure)
    end
  end

  defp as_it_stands(actor, id, failure) do
    case read(actor, id) do
      {:ok, %{status: :settled} = found} -> {:settled, found, found.receipt}
      _unread -> {:error, failure}
    end
  end

  # Called only while the intent's row lock is held: the status read under the
  # lock decides, so an applied intent is never carried out again. An effect
  # that fails, or cannot be marked applied, rolls the whole transaction back.
  defp carry_out_once(_actor, %{status: :applied} = locked, _request),
    do: {:applied, locked, locked.receipt}

  defp carry_out_once(actor, %{status: :settled} = locked, request) do
    with {:ok, :complete} <- carry_out(locked, locked.receipt, actor, request),
         {:ok, applied} <- RegentPayments.mark_applied(locked, actor: actor) do
      {:applied, applied, locked.receipt}
    else
      {:ok, :incomplete} -> {:settled, locked, locked.receipt}
      {:error, reason} -> {:error, reason}
    end
  end

  # What the money bought, carried out by the offer behind the intent. A
  # failure is written to the log with what a person needs to finish it by
  # hand; the payment and its receipt stand either way.
  defp carry_out(settled, receipt, actor, request) do
    case Offer.for_kind!(settled.kind).carry_out(settled, receipt, actor, request.context) do
      {:ok, done} when done in [:complete, :incomplete] ->
        {:ok, done}

      {:error, reason} ->
        Logger.warning(
          "Payment #{settled.id} (#{settled.kind}) settled but its effect was not carried out " <>
            "(payer #{actor.id}): #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp record_receipt(actor, found, payment, body) do
    RegentPayments.record_payment_receipt(
      %{
        payment_intent_id: found.id,
        payment_identifier: found.payment_identifier,
        payer_address: get_in(payment, ["payload", "authorization", "from"]),
        network: found.network,
        asset: found.asset,
        amount_atomic: found.amount_atomic,
        facilitator: facilitator_url(),
        transaction_hash: transaction_hash(body),
        payment_response: body,
        settled_at: DateTime.utc_now()
      },
      actor: actor
    )
  end

  defp transaction_hash(%{"transaction" => hash}) when is_binary(hash) and hash != "", do: hash
  defp transaction_hash(_body), do: nil

  defp facilitator_url do
    :regent_payments |> Application.get_env(@facilitator, []) |> Keyword.fetch!(:url)
  end

  # Reading an intent

  @doc "The intent `id` as it stands, with its receipt, if it is `actor`'s."
  @spec read(struct(), String.t()) :: {:ok, PaymentIntent.t()} | {:error, term()}
  def read(actor, id) do
    intent(actor, id, fn id, opts ->
      RegentPayments.get_payment_intent(id, Keyword.put(opts, :load, [:receipt]))
    end)
  end

  defp intent(actor, id, read) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> owned(found_or_missing(read.(uuid, actor: actor)), actor)
      :error -> {:error, :not_found}
    end
  end

  # Ash filters out other payers' intents. Keep this ownership check as defense
  # in depth, together with the offer's own say on who may pay for it; denied
  # reads reveal neither the record nor its existence.
  defp owned({:ok, found}, actor) do
    if found.actor_profile_id == actor.id and Offer.for_kind!(found.kind).payer?(actor),
      do: {:ok, found},
      else: {:error, :not_found}
  end

  defp owned({:error, failure}, _actor), do: {:error, failure}

  defp found_or_missing({:ok, nil}), do: {:error, :not_found}
  defp found_or_missing({:ok, record}), do: {:ok, record}

  defp found_or_missing({:error, error}) do
    if missing?(error), do: {:error, :not_found}, else: {:error, error}
  end

  @doc "Whether an error means there is no such record."
  @spec missing?(term()) :: boolean()
  def missing?(%Ash.Error.Query.NotFound{}), do: true
  def missing?(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &missing?/1)
  def missing?(_error), do: false

  # The terms

  @doc """
  The x402 terms for an intent, with `error` as the sentence asking for
  payment and `resource_url` as the site's address for paying it.
  """
  @spec terms(PaymentIntent.t(), String.t(), String.t()) :: map()
  def terms(found, error, resource_url) do
    %{
      "x402Version" => 2,
      "error" => error,
      "resource" => %{
        "url" => resource_url,
        "description" => found.effect_summary,
        "mimeType" => "application/json"
      },
      "accepts" => [requirement(found)],
      "extensions" => %{"paymentIdentifier" => identifier_extension(found)}
    }
  end

  @doc """
  The one x402 requirement an intent accepts. It is read from the stored
  intent every time, so what a payer signs for is what was frozen when the
  intent was prepared.
  """
  @spec requirement(PaymentIntent.t()) :: map()
  def requirement(found) do
    %{
      "scheme" => "exact",
      "network" => found.network,
      "amount" => Integer.to_string(found.amount_atomic),
      "asset" => found.asset,
      "payTo" => Map.fetch!(found.payload, "pay_to_address"),
      "maxTimeoutSeconds" => @max_timeout_seconds,
      "extra" => USDC.signing_domain()
    }
  end

  @doc "The intent's payment identifier as the x402 extension carries it."
  @spec identifier_extension(PaymentIntent.t()) :: String.t()
  def identifier_extension(found) do
    {:ok, encoded} = PaymentIdentifier.encode(found.payment_identifier)
    encoded
  end

  @doc "What was paid and when, as the receipt records it."
  @spec receipt_payload(PaymentReceipt.t()) :: map()
  def receipt_payload(receipt) do
    %{
      transaction_hash: receipt.transaction_hash,
      payer_address: receipt.payer_address,
      settled_at: receipt.settled_at
    }
  end
end
