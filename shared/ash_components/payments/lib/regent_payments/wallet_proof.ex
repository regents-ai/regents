defmodule RegentPayments.WalletProof do
  @moduledoc """
  How a caller with no signed-in wallet proves it speaks for one.

  A hosted MCP connection carries no signed-in wallet. Paying proves the
  wallet by the payment's own signature; an action that moves money without a
  payment has the wallet sign for that exact action instead. The site answers
  with EIP-712 typed data naming the action, what it acts on, the wallet and a
  challenge the site signed, good for ten minutes; the caller has any EIP-712
  signer sign it and calls again with the challenge and the signature. The
  signer recovered from the signature has to be the wallet named, and the
  challenge has to be the site's and unexpired, so a signature proves one
  action on one thing by one wallet, and nothing else.

  The typed data's domain is the site's own, from its configuration:

      config :regent_payments,
        wallet_proof: [name: "MySite", version: "1", endpoint: MySiteWeb.Endpoint]

  The challenge is signed with the endpoint's `secret_key_base`, as a Phoenix
  token would be.

  Nothing here holds a key or moves money: the wallet signs, this checks.
  """

  alias RegentPayments.USDC

  @salt "mcp wallet proof"
  @max_age_seconds 10 * 60

  @typedoc """
  One action by one wallet. `subjects` names what it acts on, in the order
  they are signed, as EIP-712 field names and the ids given for them, such as
  `[{"reportId", report_id}, {"replyId", reply_id}]`.
  """
  @type action :: %{
          action: String.t(),
          subjects: [{String.t(), String.t()}],
          wallet: String.t()
        }

  @typedoc "Why a proof was refused."
  @type refusal ::
          :challenge_expired
          | :challenge_mismatch
          | :signature_unreadable
          | :other_wallet
          | :incomplete_proof

  @doc "How long a challenge stands, in seconds."
  @spec max_age_seconds() :: pos_integer()
  def max_age_seconds, do: @max_age_seconds

  @doc """
  What a caller's `params` prove for `action`: `:ok` when they carry the
  wallet's signature over a challenge issued for exactly this action; a fresh
  challenge to sign when they carry neither `challenge` nor `signature`; or
  the refusal, `:incomplete_proof` when they carry only one of the two.
  """
  @spec prove(action(), map()) ::
          :ok | {:sign, %{challenge: String.t(), typed_data: map()}} | {:error, refusal()}
  def prove(action, %{"challenge" => challenge, "signature" => signature})
      when is_binary(challenge) and is_binary(signature),
      do: verify(action, challenge, signature)

  def prove(action, params) do
    if Map.has_key?(params, "challenge") or Map.has_key?(params, "signature"),
      do: {:error, :incomplete_proof},
      else: {:sign, challenge(action)}
  end

  @doc """
  A fresh challenge for `action`, and the typed data to sign, in the shape
  `eth_signTypedData_v4` takes.
  """
  @spec challenge(action()) :: %{challenge: String.t(), typed_data: map()}
  def challenge(action) do
    challenge = Plug.Crypto.sign(secret_key_base(), @salt, action)

    %{
      challenge: challenge,
      typed_data: action |> typed_data(challenge) |> Ethers.TypedData.to_eip712_json()
    }
  end

  @doc """
  Whether `signature` is `action`'s wallet signing the typed data this site
  issued as `challenge` for exactly this action.
  """
  @spec verify(action(), String.t(), String.t()) :: :ok | {:error, refusal()}
  def verify(action, challenge, signature) do
    with :ok <- issued_for(action, challenge),
         {:ok, signer} <- signer(typed_data(action, challenge), signature) do
      if String.downcase(signer) == action.wallet, do: :ok, else: {:error, :other_wallet}
    end
  end

  defp issued_for(action, challenge) do
    case Plug.Crypto.verify(secret_key_base(), @salt, challenge, max_age: @max_age_seconds) do
      {:ok, ^action} -> :ok
      {:ok, _other_action} -> {:error, :challenge_mismatch}
      {:error, :expired} -> {:error, :challenge_expired}
      {:error, _invalid} -> {:error, :challenge_mismatch}
    end
  end

  defp signer(typed_data, signature) do
    case Ethers.TypedData.recover_signer(typed_data, signature) do
      "0x" <> _ = address -> {:ok, address}
      {:error, _reason} -> {:error, :signature_unreadable}
    end
  end

  defp typed_data(action, challenge) do
    subject_fields =
      Enum.map(action.subjects, fn {name, _id} -> %{name: name, type: "string"} end)

    fields =
      [%{name: "action", type: "string"}] ++
        subject_fields ++
        [%{name: "wallet", type: "address"}, %{name: "challenge", type: "string"}]

    message =
      Map.merge(Map.new(action.subjects), %{
        "action" => action.action,
        "wallet" => action.wallet,
        "challenge" => challenge
      })

    Ethers.TypedData.new!(
      types: %{"WalletAction" => fields},
      primary_type: "WalletAction",
      domain: [name: setting(:name), version: setting(:version), chain_id: USDC.chain_id()],
      message: message
    )
  end

  defp secret_key_base, do: setting(:endpoint).config(:secret_key_base)

  defp setting(key) do
    :regent_payments |> Application.fetch_env!(:wallet_proof) |> Keyword.fetch!(key)
  end
end
