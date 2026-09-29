defmodule RegentPayments.Test.Actor do
  @moduledoc """
  A signed-in profile as a site hands it to the library: its id, the wallet
  it signed in with, and the door it came through.
  """
  defstruct [:id, :wallet_address, origin: :page]
end

defmodule RegentPayments.Test.Endpoint do
  @moduledoc "The one thing the library asks of a site's endpoint: its secret key base."
  def config(:secret_key_base), do: String.duplicate("regent payments test secret ", 3)
end

defmodule RegentPayments.Test.Terms do
  @moduledoc """
  The terms both test offers freeze: an amount between 0.01 and 100 USDC,
  paid to the wallet named, for the target named.
  """

  alias RegentPayments.Offer

  def freeze(%{amount_atomic: amount, pay_to: pay_to, target_id: target_id}) do
    with :ok <- Offer.amount_between(amount, 10_000, 100_000_000) do
      {:ok,
       %{
         amount_atomic: amount,
         pay_to_address: pay_to,
         target_id: target_id,
         payload: %{"target_id" => target_id},
         recipient_snapshot: [%{"wallet_address" => pay_to}],
         effect_summary: "Pays #{RegentPayments.USDC.format(amount)} USDC to #{pay_to}."
       }}
    end
  end
end

defmodule RegentPayments.Test.Effects do
  @moduledoc """
  The test site's own row for what a payment bought, written through the
  library's repository as a site's offer writes it: one row per intent,
  counting each carry out that was saved.
  """

  alias RegentPayments.TestRepo

  @doc "Saves one carry out of `intent_id`, in whatever transaction is open."
  def write!(intent_id) do
    TestRepo.query!(
      "INSERT INTO payment_effects (payment_intent_id) VALUES ($1) " <>
        "ON CONFLICT (payment_intent_id) DO UPDATE SET carried_out = payment_effects.carried_out + 1",
      [Ecto.UUID.dump!(intent_id)]
    )
  end

  @doc "How many carry outs of `intent_id` were saved."
  def carried_out(intent_id) do
    case TestRepo.query!(
           "SELECT carried_out FROM payment_effects WHERE payment_intent_id = $1",
           [Ecto.UUID.dump!(intent_id)]
         ).rows do
      [[count]] -> count
      [] -> 0
    end
  end
end

defmodule RegentPayments.Test.DirectOffer do
  @moduledoc """
  An offer like a tip: only a page's profile may pay for it, and a settled
  intent whose effect is incomplete is carried out again on the next call.
  Its effect writes the site's row and is complete unless the caller's
  context says otherwise: `:incomplete`, or `:fail` after writing. A
  `watcher` in the context is told when a carry out starts and holds it
  until it answers `:go`.
  """
  @behaviour RegentPayments.Offer

  @impl true
  def kind, do: :direct
  @impl true
  def target_type, do: :profile
  @impl true
  def payer?(actor), do: actor.origin == :page
  @impl true
  def freeze(input, _actor), do: RegentPayments.Test.Terms.freeze(input)
  @impl true
  def carry_out(intent, _receipt, _actor, context) do
    held(context)
    RegentPayments.Test.Effects.write!(intent.id)

    case Map.get(context, :outcome, :complete) do
      :fail -> {:error, :effect_failed}
      done -> {:ok, done}
    end
  end

  @impl true
  def resumes?, do: true

  defp held(%{watcher: watcher}) do
    send(watcher, {:carrying, self()})

    receive do
      :go -> :ok
    after
      5_000 -> :ok
    end
  end

  defp held(_context), do: :ok
end

defmodule RegentPayments.Test.PublishOffer do
  @moduledoc """
  An offer whose effect cannot be carried out, like a report that fails to
  publish, and which is never carried out again: any profile may pay for it.
  """
  @behaviour RegentPayments.Offer

  @impl true
  def kind, do: :publish
  @impl true
  def target_type, do: :report
  @impl true
  def payer?(_actor), do: true
  @impl true
  def freeze(input, _actor), do: RegentPayments.Test.Terms.freeze(input)
  @impl true
  def carry_out(_intent, _receipt, _actor, _context), do: {:error, :publish_failed}
  @impl true
  def resumes?, do: false
end

defmodule RegentPayments.Test.WalletSigner do
  @moduledoc """
  A synthetic wallet for tests: a key made for the run, its address, and its
  signature over what a page payment's review asks it to sign. It never
  reaches a real chain.
  """

  @doc "A fresh key and its lowercased address."
  def new do
    key = :crypto.strong_rand_bytes(32)
    {:ok, address} = X402.EIP3009.derive_address(key)
    %{key: key, address: String.downcase(address)}
  end

  @doc "`wallet`'s signature over the typed data in `review`'s one signature step."
  def sign(%{key: key}, %{steps: [%{kind: "signature", typed_data: typed_data}]}) do
    {:ok, digest} = X402.EIP3009.eip712_digest(typed_data["domain"], typed_data["message"])
    {:ok, {signature, recovery}} = ExSecp256k1.sign_compact(digest, key)
    "0x" <> Base.encode16(signature <> <<recovery + 27>>, case: :lower)
  end
end
