defmodule RegentPayments.Operator do
  @moduledoc """
  Sends a transaction signed with one of the site's own keys on Base and waits
  for the chain to take it. `RegentPayments.FeeForward` sends through it.

  The key travels only into the local signer. An exception raised while
  sending comes from a call handed that key, so callers name it and never
  carry it.
  """

  alias Ethers.TxData
  alias RegentChain.BuilderCode

  @receipt_every_ms 2_000
  @receipt_tries 30

  @typedoc "The wallet that signs, and the Base endpoint it sends through."
  @type signer :: %{address: String.t(), private_key: String.t(), rpc_url: String.t()}

  @doc """
  Hands `tx_data` for `to` to the chain, signed by `signer`, and returns its
  hash. The calldata ends with Regent's Base Builder Code
  (`RegentChain.BuilderCode`), so Base credits Regent with the transaction. It
  takes the wallet's next nonce after every transaction the chain already
  holds, mined or still waiting, so a send never replaces an earlier one that
  has not landed yet.
  """
  @spec send(TxData.t(), String.t(), signer()) :: {:ok, String.t()} | {:error, term()}
  def send(%TxData{data: data} = tx_data, to, signer) do
    rpc_opts = [url: signer.rpc_url]
    tx_data = %{tx_data | data: data <> Ethers.Utils.hex_decode!(BuilderCode.suffix())}

    with {:ok, nonce} <-
           Ethers.get_transaction_count(signer.address, block: "pending", rpc_opts: rpc_opts) do
      Ethers.send_transaction(tx_data,
        from: signer.address,
        to: to,
        nonce: nonce,
        signer: Ethers.Signer.Local,
        signer_opts: [private_key: signer.private_key],
        rpc_opts: rpc_opts
      )
    end
  end

  @doc """
  Waits for the chain to take the transaction: the receipt is read every two
  seconds, for a minute at most. `{:error, :not_mined}` means it may
  still land.
  """
  @spec mined(String.t(), signer()) :: :ok | {:error, :reverted | :not_mined}
  def mined(tx_hash, signer), do: mined(tx_hash, signer.rpc_url, @receipt_tries)

  @doc "What the chain says of the transaction now, read once: `:ok`, `:reverted` or `:not_yet`."
  @spec status(String.t(), String.t()) :: :ok | :reverted | :not_yet
  def status(tx_hash, rpc_url) do
    case receipt_status(tx_hash, rpc_url) do
      "0x1" -> :ok
      status when is_binary(status) -> :reverted
      nil -> :not_yet
    end
  end

  defp mined(_tx_hash, _rpc_url, 0), do: {:error, :not_mined}

  defp mined(tx_hash, rpc_url, tries_left) do
    case status(tx_hash, rpc_url) do
      :ok ->
        :ok

      :reverted ->
        {:error, :reverted}

      :not_yet ->
        Process.sleep(@receipt_every_ms)
        mined(tx_hash, rpc_url, tries_left - 1)
    end
  end

  # A read that fails, or raises, counts as not yet.
  defp receipt_status(tx_hash, rpc_url) do
    case Ethers.get_transaction_receipt(tx_hash, rpc_opts: [url: rpc_url]) do
      {:ok, %{"status" => status}} when is_binary(status) -> status
      _not_yet -> nil
    end
  rescue
    _exception -> nil
  end
end
