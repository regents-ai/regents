defmodule RegentPayments.MCP do
  @moduledoc """
  What a site's hosted MCP tools need to take a payment.

  The hosted door carries no signed-in wallet, so a tool that acts for a
  wallet names it in its arguments, and the wallet is proven per call, never
  taken on the caller's word: a payment by the signed x402 payment, which has
  to come from the wallet named (the `payer` of
  `RegentPayments.Purchase.execute/3`), and an action that moves money
  without a payment by `RegentPayments.WalletProof`.
  """

  @address ~r/\A0x[0-9a-fA-F]{40}\z/

  @doc "The wallet a tool names, lowercased, when it is a Base wallet address."
  @spec wallet(term()) :: {:ok, String.t()} | :error
  def wallet(address) when is_binary(address) do
    if Regex.match?(@address, address), do: {:ok, String.downcase(address)}, else: :error
  end

  def wallet(_address), do: :error

  @doc """
  The signed payment in a request's `_meta`, where the x402 MCP transport
  carries it as `x402/payment`, or `nil` when none came.
  """
  @spec payment(map() | nil) :: map() | nil
  def payment(meta) do
    case X402.MCP.fetch_payment(%{"_meta" => meta}) do
      {:ok, payment} -> payment
      :error -> nil
    end
  end
end
