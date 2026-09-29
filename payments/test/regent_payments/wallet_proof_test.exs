defmodule RegentPayments.WalletProofTest do
  @moduledoc """
  A wallet proving one action by signing the site's challenge for it: only the
  named wallet's signature over a challenge issued for exactly that action
  proves it.
  """

  use ExUnit.Case, async: true

  alias RegentPayments.Test.WalletSigner
  alias RegentPayments.WalletProof

  setup do
    wallet = WalletSigner.new()

    action = %{
      action: "accept_solution",
      subjects: [{"reportId", Ecto.UUID.generate()}, {"replyId", Ecto.UUID.generate()}],
      wallet: wallet.address
    }

    %{wallet: wallet, action: action}
  end

  test "without a challenge the caller is handed one to sign", c do
    assert {:sign, %{challenge: challenge, typed_data: typed_data}} =
             WalletProof.prove(c.action, %{})

    assert is_binary(challenge)
    assert typed_data["primaryType"] == "WalletAction"
    assert typed_data["domain"]["name"] == "Regent test"
    assert String.downcase(typed_data["message"]["wallet"]) == c.wallet.address

    assert Enum.map(typed_data["types"]["WalletAction"], & &1["name"]) ==
             ~w(action reportId replyId wallet challenge)
  end

  test "the named wallet's signature over its challenge proves the action", c do
    %{challenge: challenge, typed_data: typed_data} = WalletProof.challenge(c.action)
    signature = sign_typed(c.wallet, typed_data)

    assert :ok =
             WalletProof.prove(c.action, %{"challenge" => challenge, "signature" => signature})
  end

  test "another wallet's signature proves nothing", c do
    %{challenge: challenge, typed_data: typed_data} = WalletProof.challenge(c.action)
    forged = sign_typed(WalletSigner.new(), typed_data)

    assert {:error, :other_wallet} = WalletProof.verify(c.action, challenge, forged)
  end

  test "a challenge issued for another action proves nothing", c do
    %{challenge: challenge, typed_data: typed_data} = WalletProof.challenge(c.action)
    signature = sign_typed(c.wallet, typed_data)
    other = %{c.action | action: "withdraw_priority_report"}

    assert {:error, :challenge_mismatch} = WalletProof.verify(other, challenge, signature)
    assert {:error, :challenge_mismatch} = WalletProof.verify(c.action, "forged", signature)
  end

  test "an unreadable signature or half a proof is refused", c do
    %{challenge: challenge} = WalletProof.challenge(c.action)

    assert {:error, :signature_unreadable} = WalletProof.verify(c.action, challenge, "0x1234")
    assert {:error, :incomplete_proof} = WalletProof.prove(c.action, %{"challenge" => challenge})
  end

  # Signs the typed data exactly as it was handed out, as a wallet would: the
  # chain id travels as a decimal string in EIP-712 JSON and is a number when
  # hashed.
  defp sign_typed(%{key: key}, typed_data) do
    domain = typed_data["domain"]

    Ethers.TypedData.new!(
      types: Map.delete(typed_data["types"], "EIP712Domain"),
      primary_type: typed_data["primaryType"],
      domain: [
        name: domain["name"],
        version: domain["version"],
        chain_id: String.to_integer(domain["chainId"])
      ],
      message: typed_data["message"]
    )
    |> Ethers.sign_typed_data!(signer: Ethers.Signer.Local, signer_opts: [private_key: key])
  end
end
