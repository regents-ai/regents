defmodule RegentPayments.Balance do
  @moduledoc """
  A person's USDC Balance: what their own wallet holds in USDC on Base, read
  from the chain itself.

  Regents never holds anyone's money, so the only balance it can honestly
  report is the one the USDC contract reports for the person's wallet: one
  `eth_call` of `balanceOf(address)` through the Base read endpoint the site
  configures as `config :regent_payments, base_rpc_url: ...`. A site started
  without that endpoint says so rather than guessing.
  """

  alias RegentPayments.USDC

  # The first four bytes of keccak256("balanceOf(address)").
  @balance_of_selector "70a08231"

  @receive_timeout_ms 10_000

  @doc "Whether Base can be read for balances: the endpoint is a real http(s) address."
  @spec configured?() :: boolean()
  def configured?, do: is_binary(rpc_url())

  @doc """
  The wallet's USDC Balance in atomic units (six decimals), read on chain.
  An address that is not `0x` and forty hex digits answers `:invalid_address`
  without calling the chain.
  """
  @spec usdc_balance_atomic(String.t()) ::
          {:ok, non_neg_integer()} | {:error, :invalid_address | :not_configured | :rpc_failed}
  def usdc_balance_atomic(wallet_address) do
    with {:ok, address} <- address_hex(wallet_address) do
      case rpc_url() do
        nil -> {:error, :not_configured}
        url -> read_balance_of(url, address)
      end
    end
  end

  defp address_hex("0x" <> hex = address) when byte_size(hex) == 40 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, _bytes} -> {:ok, address}
      :error -> {:error, :invalid_address}
    end
  end

  defp address_hex(_address), do: {:error, :invalid_address}

  # Only a web address can be called. Anything else is treated as unset rather
  # than handed to the client, whose refusal would repeat the value in a log,
  # and the value may carry the provider's key.
  defp rpc_url do
    with url when is_binary(url) <- Application.get_env(:regent_payments, :base_rpc_url),
         %URI{scheme: scheme, host: host}
         when scheme in ["http", "https"] and is_binary(host) and host != "" <- URI.parse(url) do
      url
    else
      _unset -> nil
    end
  end

  defp read_balance_of(url, wallet_address) do
    request = %{
      jsonrpc: "2.0",
      id: 1,
      method: "eth_call",
      params: [%{to: USDC.asset(), data: balance_of_calldata(wallet_address)}, "latest"]
    }

    # The endpoint's address may carry the provider's key, so neither the
    # request nor what went wrong with it is logged or repeated to the caller.
    case Req.post(url, json: request, receive_timeout: @receive_timeout_ms) do
      {:ok, %Req.Response{status: 200, body: %{"result" => result}}} -> parse_word(result)
      _failed -> {:error, :rpc_failed}
    end
  end

  # The ABI encoding of balanceOf(address): the selector, then the address
  # left-padded to one 32-byte word.
  defp balance_of_calldata("0x" <> address) do
    "0x" <> @balance_of_selector <> String.pad_leading(address, 64, "0")
  end

  # The answer is one 32-byte word holding an unsigned integer.
  defp parse_word("0x" <> hex) when byte_size(hex) == 64 do
    case Integer.parse(hex, 16) do
      {value, ""} when value >= 0 -> {:ok, value}
      _malformed -> {:error, :rpc_failed}
    end
  end

  defp parse_word(_other), do: {:error, :rpc_failed}
end
