defmodule RegentPayments.FeeForward do
  @moduledoc """
  The paid-fix fee route: hands a fee on from the site's operator wallet to
  the REGENT revenue staking contract on Base, as revenue tagged with the
  site's source tag and referenced to the wallet that paid it.

  The fee first settles into the operator wallet as a plain USDC transfer,
  which is all an x402 payment can be. From there it takes two transactions
  signed with the operator key, in this order: an approval of exactly the fee
  to the staking contract, and the deposit itself once the approval is on the
  chain. The site decides when to forward, writes down what came of it, and
  re-runs a fee that could not be forwarded.
  """

  alias Ethers.Contracts.ERC20
  alias RegentPayments.USDC

  @receipt_every_ms 2_000
  @receipt_tries 30

  defmodule Staking do
    @moduledoc """
    The one function of the REGENT revenue staking contract a fee is handed
    to, `depositUSDC(amount, sourceTag, sourceRef)`, from the interface the
    Autolaunch contracts pin (`IRegentRevenueStakingMinimal`).
    """

    use Ethers.Contract,
      abi:
        ~s([{"type":"function","name":"depositUSDC","inputs":[{"name":"amount","type":"uint256","internalType":"uint256"},{"name":"sourceTag","type":"bytes32","internalType":"bytes32"},{"name":"sourceRef","type":"bytes32","internalType":"bytes32"}],"outputs":[{"name":"received","type":"uint256","internalType":"uint256"}],"stateMutability":"nonpayable"}])
  end

  @typedoc "The operator wallet that signs, and the Base endpoint it sends through."
  @type signer :: %{address: String.t(), private_key: String.t(), rpc_url: String.t()}

  @doc "The tag a deposit carries on the chain, as the contract's 32 bytes."
  @spec source_tag(String.t()) :: <<_::256>>
  def source_tag(tag), do: String.pad_trailing(tag, 32, <<0>>)

  @doc "The reference a deposit carries: the paying wallet, left-padded to 32 bytes."
  @spec source_ref(String.t()) :: <<_::256>>
  def source_ref("0x" <> hex) when byte_size(hex) == 40 do
    <<0::size(96), Base.decode16!(hex, case: :mixed)::binary-size(20)>>
  end

  @doc """
  Sends the approval and then the deposit for the fee settled by intent
  `intent_id`, and returns the deposit's transaction hash once the chain has
  it. `opts` names the `staking` contract, the operator `signer` and the
  `source_tag` the deposit carries.
  """
  @spec submit(Ash.UUID.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def submit(intent_id, opts) do
    staking = Keyword.fetch!(opts, :staking)
    signer = Keyword.fetch!(opts, :signer)
    tag = opts |> Keyword.fetch!(:source_tag) |> source_tag()

    with {:ok, %{amount: amount, payer: payer}} <- payment(intent_id),
         {:ok, approval} <- send(ERC20.approve(staking, amount), USDC.asset(), signer),
         :ok <- mined(approval, signer),
         {:ok, deposit} <-
           send(Staking.deposit_usdc(amount, tag, source_ref(payer)), staking, signer),
         :ok <- mined(deposit, signer) do
      {:ok, deposit}
    end
  rescue
    # Whatever went wrong, the exception is raised from a call that was handed
    # the operator key, so it is named and not carried.
    _exception -> {:error, :submit_failed}
  end

  # The fee and the wallet it came from, as the settled payment recorded them.
  # The site's own worker reads the payment it was handed, answering to no
  # request, so authorization is set aside deliberately.
  defp payment(intent_id) do
    case RegentPayments.get_payment_intent(intent_id, authorize?: false, load: [:receipt]) do
      {:ok, %{amount_atomic: amount, receipt: %{payer_address: payer}}} when is_binary(payer) ->
        {:ok, %{amount: amount, payer: payer}}

      {:ok, _no_receipt} ->
        {:error, :no_receipt}

      {:error, error} ->
        {:error, error}
    end
  end

  defp send(tx_data, to, signer) do
    Ethers.send_transaction(tx_data,
      from: signer.address,
      to: to,
      signer: Ethers.Signer.Local,
      signer_opts: [private_key: signer.private_key],
      rpc_opts: [url: signer.rpc_url]
    )
  end

  # Waits for the chain to take the transaction: Base seals a block every two
  # seconds, so the receipt is read on that beat, for a minute at most.
  defp mined(tx_hash, signer), do: mined(tx_hash, signer, @receipt_tries)

  defp mined(_tx_hash, _signer, 0), do: {:error, :not_mined}

  defp mined(tx_hash, signer, tries_left) do
    case Ethers.get_transaction_receipt(tx_hash, rpc_opts: [url: signer.rpc_url]) do
      {:ok, %{"status" => "0x1"}} ->
        :ok

      {:ok, %{"status" => _reverted}} ->
        {:error, {:reverted, tx_hash}}

      _not_yet ->
        Process.sleep(@receipt_every_ms)
        mined(tx_hash, signer, tries_left - 1)
    end
  end
end
