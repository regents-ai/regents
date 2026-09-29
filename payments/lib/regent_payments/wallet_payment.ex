defmodule RegentPayments.WalletPayment do
  @moduledoc """
  Paying from a page, with the wallet the person signed in with.

  The library writes the USDC transfer authorization itself, for one wallet,
  and hands it to the page as a `RegentChain.Review` with a single signature
  step. The page's wallet signs exactly that and sends back the signature
  alone. The library rebuilds the same authorization, checks the signature
  came from that wallet, and only then puts the payment through
  `RegentPayments.Purchase`.

  The only wallet that may sign is the one the person signed in with, when the
  page has it open (`signer/2`). Nothing a page sends changes what is signed:
  the authorization is worked out again from the stored intent and the signer
  on every call.

  The authorization is the same every time for one intent and one wallet: it
  runs until the intent's terms expire, and its nonce comes from the intent's
  payment identifier and the wallet. A second press signs the same
  authorization, and USDC moves it at most once.

  The actor is the site's signed-in profile: it carries its `id` and the
  `wallet_address` it signed in with, which is `nil` for a profile without one.
  """

  alias RegentChain.Review
  alias RegentPayments.PaymentIntent
  alias RegentPayments.Purchase
  alias RegentPayments.USDC
  alias X402.EIP3009

  @step "pay"
  @address ~r/\A0x[0-9a-fA-F]{40}\z/
  @signature ~r/\A0x[0-9a-fA-F]{130}\z/

  @transfer_types %{
    "EIP712Domain" => [
      %{"name" => "name", "type" => "string"},
      %{"name" => "version", "type" => "string"},
      %{"name" => "chainId", "type" => "uint256"},
      %{"name" => "verifyingContract", "type" => "address"}
    ],
    "TransferWithAuthorization" => [
      %{"name" => "from", "type" => "address"},
      %{"name" => "to", "type" => "address"},
      %{"name" => "value", "type" => "uint256"},
      %{"name" => "validAfter", "type" => "uint256"},
      %{"name" => "validBefore", "type" => "uint256"},
      %{"name" => "nonce", "type" => "bytes32"}
    ]
  }

  @typedoc """
  Where a page's payment stands. Besides `Purchase`'s own answers: the review
  its wallet is to sign; no wallet that could sign, on the page or on the
  profile; the page's wallet is not the one signed in with, with the note to
  show beside the button; or a signature or payment that was refused, with
  the reason.
  """
  @type answer ::
          {:review, PaymentIntent.t(), Review.t()}
          | {:wallet_unavailable, Ash.UUID.t()}
          | {:wallet_mismatch, Ash.UUID.t(), String.t()}
          | {:payment_refused, Ash.UUID.t(), String.t()}
          | Purchase.answer()

  @doc """
  A page's payment for `actor`'s intent `id`. `params` carries the page's
  `active_wallet` and, once signed, the `review_id` and `signature`.

  Unsigned, it answers with what the signed-in wallet is to sign, when the
  page has that wallet open; a payment that already went through is read back
  without any wallet. Signed, the signature must be that wallet's over what
  the library wrote, and only then is the payment verified and settled.
  `context` travels to the offer that carries the payment out.
  """
  @spec pay(struct(), String.t(), map(), map()) :: answer()
  def pay(actor, id, params, context) do
    wallet = wallet(actor, params)

    with {:ok, found} <- Purchase.read(actor, id),
         {:ok, payment, payer} <- signed_payment(found, wallet, params) do
      request = %{payment: payment, payer: payer, context: context}

      case Purchase.execute(actor, found.id, request) do
        {:payment_required, waiting} -> review_or_wallet(waiting, wallet)
        {:payment_rejected, refused, reason} -> {:payment_refused, refused.id, reason}
        answer -> answer
      end
    end
  end

  # A profile signed in without a wallet, or a page with no wallet open, has
  # no wallet that could sign.
  defp wallet(actor, params) do
    case {signed_in(actor), active_wallet(params)} do
      {nil, _active} -> :wallet_unavailable
      {_signed_in, nil} -> :wallet_unavailable
      {signed_in, active} -> matching_wallet(signed_in, active)
    end
  end

  defp matching_wallet(signed_in, active) do
    case signer(signed_in, active) do
      nil -> {:wallet_mismatch, mismatch_note(signed_in, active)}
      signer -> {:ok, signer}
    end
  end

  defp signed_payment(found, {:ok, signer}, %{"signature" => _signed} = params) do
    case payment(found, signer, params) do
      {:ok, payment} -> {:ok, payment, signer}
      {:refused, reason} -> {:payment_refused, found.id, reason}
    end
  end

  defp signed_payment(found, wallet, %{"signature" => _signed}), do: no_wallet(found, wallet)
  defp signed_payment(_found, _wallet, _unsigned), do: {:ok, nil, nil}

  defp review_or_wallet(waiting, {:ok, signer}), do: {:review, waiting, review(waiting, signer)}
  defp review_or_wallet(waiting, wallet), do: no_wallet(waiting, wallet)

  defp no_wallet(found, :wallet_unavailable), do: {:wallet_unavailable, found.id}
  defp no_wallet(found, {:wallet_mismatch, note}), do: {:wallet_mismatch, found.id, note}

  @doc "The page's active wallet as it reported it, lowercased, or `nil`."
  @spec active_wallet(map()) :: String.t() | nil
  def active_wallet(%{"active_wallet" => address}) when is_binary(address) do
    if Regex.match?(@address, address), do: String.downcase(address)
  end

  def active_wallet(_params), do: nil

  @doc "The wallet `profile` signed in with, lowercased, or `nil` when it has none."
  @spec signed_in(struct()) :: String.t() | nil
  def signed_in(%{wallet_address: address}) when is_binary(address), do: String.downcase(address)
  def signed_in(_profile), do: nil

  @doc """
  The wallet that may sign: the page's `active` wallet when it is the one
  signed in with. Any other wallet, or none, may not.
  """
  @spec signer(String.t(), String.t() | nil) :: String.t() | nil
  def signer(signed_in, active), do: if(active == signed_in, do: active)

  @doc "The note beside the button while the page's wallet is another one, naming both."
  @spec mismatch_note(String.t(), String.t()) :: String.t()
  def mismatch_note(signed_in, active) do
    "You're signed in as #{short(signed_in)}, but your wallet app has #{short(active)} open."
  end

  @doc "What `signer` signs to pay for `found`, as the page is handed it."
  @spec review(PaymentIntent.t(), String.t()) :: Review.t()
  def review(found, signer) do
    Review.new(found.id, signer, chain(), [Review.signature(@step, typed_data(found, signer))])
  end

  @doc """
  The x402 payment `signer`'s `signature` makes for `found`, when it signs the
  review with `review_id`. The review is built again here, and the signature
  must recover to `signer` over the library's own copy of what was signed.
  """
  @spec payment(PaymentIntent.t(), String.t(), map()) :: {:ok, map()} | {:refused, String.t()}
  def payment(found, signer, %{"review_id" => review_id, "signature" => signature})
      when is_binary(review_id) and is_binary(signature) do
    review = review(found, signer)
    %{typed_data: typed_data} = Review.find(review, @step)

    cond do
      review.id != review_id ->
        {:refused, "Those payment terms have changed since your wallet saw them."}

      not Regex.match?(@signature, signature) ->
        {:refused, "That signature could not be read."}

      true ->
        signed(found, signer, typed_data, with_recovery_id(signature))
    end
  end

  def payment(_found, _signer, _params), do: {:refused, "That signature could not be read."}

  defp signed(found, signer, typed_data, signature) do
    if recovered(typed_data, signature) == {:ok, signer} do
      {:ok,
       %{
         "x402Version" => 2,
         "accepted" => Purchase.requirement(found),
         "payload" => %{"signature" => signature, "authorization" => typed_data["message"]},
         "extensions" => Purchase.extensions(found)
       }}
    else
      {:refused, "That signature is not from the wallet it was asked of."}
    end
  end

  # Some wallets end a signature with 0 or 1 where USDC reads 27 or 28; both
  # say the same thing, and USDC takes only the second.
  defp with_recovery_id("0x" <> hex) do
    {rs, v} = hex |> String.downcase() |> String.split_at(128)

    case v do
      "00" -> "0x" <> rs <> "1b"
      "01" -> "0x" <> rs <> "1c"
      v -> "0x" <> rs <> v
    end
  end

  defp typed_data(found, signer) do
    requirement = Purchase.requirement(found)
    {:ok, domain} = EIP3009.domain(requirement)

    %{
      "types" => @transfer_types,
      "primaryType" => "TransferWithAuthorization",
      "domain" => %{
        "name" => domain.name,
        "version" => domain.version,
        "chainId" => domain.chain_id,
        "verifyingContract" => String.downcase(domain.verifying_contract)
      },
      "message" => %{
        "from" => signer,
        "to" => String.downcase(requirement["payTo"]),
        "value" => requirement["amount"],
        "validAfter" => "0",
        "validBefore" => Integer.to_string(DateTime.to_unix(found.expires_at)),
        "nonce" => nonce(found, signer)
      }
    }
  end

  # One nonce for one intent and one wallet, so a repeat press signs the same
  # authorization rather than a second transfer.
  defp nonce(found, "0x" <> hex) do
    "0x" <>
      Base.encode16(
        ExKeccak.hash_256(found.payment_identifier <> Base.decode16!(hex, case: :lower)),
        case: :lower
      )
  end

  defp recovered(%{"domain" => domain, "message" => message}, signature) do
    with {:ok, digest} <- EIP3009.eip712_digest(domain, message) do
      EIP3009.recover_signer(digest, signature)
    end
  end

  # The network the page's wallet signs on, as the wallet is told it: the
  # site's `payment_chain` (a name and a public endpoint for a wallet that has
  # to add the network) with the chain id of the network USDC is paid on.
  defp chain do
    :regent_payments
    |> Application.fetch_env!(:payment_chain)
    |> Map.put(:chain_id, USDC.chain_id())
  end

  defp short(address), do: RegentFormat.short_address(address)
end
