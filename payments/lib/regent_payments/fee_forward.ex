defmodule RegentPayments.FeeForward do
  @moduledoc """
  The paid-fix fee route: hands a fee on from the site's operator wallet to
  the REGENT revenue staking contract on Base, as revenue tagged with the
  site's source tag and referenced to the wallet that paid it.

  The fee first settles into the operator wallet as a plain USDC transfer,
  which is all an x402 payment can be. From there it takes two transactions
  signed with the operator key, in this order: an approval of exactly the fee
  to the staking contract, and the deposit itself once the approval is on the
  chain. The site decides when to forward and writes down what came of it.

  What comes back says whether running the forward again is safe. Until the
  deposit is handed to the chain nothing has left the operator wallet, so a
  refusal or a failed approval can simply be run again. From the moment the
  deposit is handed over, a failure is answered as `:deposit_unknown` with
  the hashes sent so far: the deposit may still land, so the site looks on
  the chain before it runs the forward again, and never re-runs it blind.

  Only a fee of the offer kind the site names, paid into the very wallet that
  signs the forward, is handed on. Nothing here remembers what was already
  forwarded: stopping a second forward of one fee is the site's job, under a
  row lock on its own record of the forward, taken before `submit/2` runs.
  """

  alias Ethers.Contracts.ERC20
  alias RegentPayments.USDC

  # Base seals a block every two seconds. Tests read receipts faster through
  # `config :regent_payments, RegentPayments.FeeForward, receipt_every_ms: ...`.
  @receipt_every_ms Application.compile_env(
                      :regent_payments,
                      [__MODULE__, :receipt_every_ms],
                      2_000
                    )
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

  @typedoc "The transactions a forward handed to the chain."
  @type sent :: %{approval: String.t(), deposit: String.t() | nil}

  @doc """
  Sends the approval and then the deposit for the fee settled by intent
  `intent_id`, and returns both transaction hashes once the chain has the
  deposit. `opts` names the offer `kind` the fee must have been paid for, the
  `staking` contract, the operator `signer` and the `source_tag` the deposit
  carries.

  Nothing was deposited, and the forward can be run again, after
  `:wrong_kind` (a fee of another offer kind), `:not_paid_to_signer` (a fee
  not paid into the signer's wallet), `:no_receipt`, `{:approval_failed, hash}`
  (the hash is nil when the approval never reached the chain) or
  `{:deposit_reverted, sent}`. After `{:deposit_unknown, sent}` the deposit
  may still land: look on the chain before running it again.
  """
  @spec submit(Ash.UUID.t(), keyword()) ::
          {:ok, %{approval: String.t(), deposit: String.t()}}
          | {:error,
             :wrong_kind
             | :not_paid_to_signer
             | :no_receipt
             | {:approval_failed, String.t() | nil}
             | {:deposit_reverted, sent()}
             | {:deposit_unknown, sent()}
             | term()}
  def submit(intent_id, opts) do
    kind = Keyword.fetch!(opts, :kind)
    staking = Keyword.fetch!(opts, :staking)
    signer = Keyword.fetch!(opts, :signer)
    tag = opts |> Keyword.fetch!(:source_tag) |> source_tag()

    with {:ok, fee} <- payment(intent_id, kind, signer.address),
         {:ok, approval} <- approved(fee.amount, staking, signer) do
      deposit = Staking.deposit_usdc(fee.amount, tag, source_ref(fee.payer))
      deposited(send_deposit(deposit, staking, signer), signer, approval)
    end
  end

  # Nothing has left the operator wallet while the approval is under way. An
  # exception raised here comes from a call handed the operator key, so it is
  # named and never carried.
  defp approved(amount, staking, signer) do
    case send(ERC20.approve(staking, amount), USDC.asset(), signer) do
      {:ok, approval} -> approval_mined(mined(approval, signer), approval)
      {:error, _reason} -> {:error, {:approval_failed, nil}}
    end
  rescue
    _exception -> {:error, {:approval_failed, nil}}
  end

  defp approval_mined(:ok, approval), do: {:ok, approval}
  defp approval_mined({:error, _reason}, approval), do: {:error, {:approval_failed, approval}}

  # A refusal of the send may still have reached the chain, so it is treated
  # as a deposit that may land, like one that was sent and not yet mined.
  defp send_deposit(deposit, staking, signer) do
    send(deposit, staking, signer)
  rescue
    _exception -> {:error, :send_failed}
  end

  defp deposited({:ok, deposit}, signer, approval) do
    sent = %{approval: approval, deposit: deposit}

    case mined(deposit, signer) do
      :ok -> {:ok, sent}
      {:error, :reverted} -> {:error, {:deposit_reverted, sent}}
      {:error, :not_mined} -> {:error, {:deposit_unknown, sent}}
    end
  end

  defp deposited({:error, _reason}, _signer, approval),
    do: {:error, {:deposit_unknown, %{approval: approval, deposit: nil}}}

  # The fee and the wallet it came from, as the settled payment recorded them.
  # The site's own worker reads the payment it was handed, answering to no
  # request, so authorization is set aside deliberately; the kind and the
  # wallet the frozen terms paid are checked instead.
  defp payment(intent_id, kind, signer_address) do
    case RegentPayments.get_payment_intent(intent_id, authorize?: false, load: [:receipt]) do
      {:ok, %{kind: ^kind} = intent} -> paid_to_signer(intent, signer_address)
      {:ok, _other_kind} -> {:error, :wrong_kind}
      {:error, error} -> {:error, error}
    end
  end

  defp paid_to_signer(intent, signer_address) do
    if String.downcase(intent.payload["pay_to_address"]) == String.downcase(signer_address),
      do: settled_fee(intent),
      else: {:error, :not_paid_to_signer}
  end

  defp settled_fee(%{amount_atomic: amount, receipt: %{payer_address: payer}})
       when is_binary(payer),
       do: {:ok, %{amount: amount, payer: payer}}

  defp settled_fee(_no_receipt), do: {:error, :no_receipt}

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
  # seconds, so the receipt is read on that beat, for a minute at most. A read
  # that fails, or raises, counts as not yet.
  defp mined(tx_hash, signer), do: mined(tx_hash, signer, @receipt_tries)

  defp mined(_tx_hash, _signer, 0), do: {:error, :not_mined}

  defp mined(tx_hash, signer, tries_left) do
    case receipt_status(tx_hash, signer) do
      "0x1" ->
        :ok

      status when is_binary(status) ->
        {:error, :reverted}

      nil ->
        Process.sleep(@receipt_every_ms)
        mined(tx_hash, signer, tries_left - 1)
    end
  end

  defp receipt_status(tx_hash, signer) do
    case Ethers.get_transaction_receipt(tx_hash, rpc_opts: [url: signer.rpc_url]) do
      {:ok, %{"status" => status}} when is_binary(status) -> status
      _not_yet -> nil
    end
  rescue
    _exception -> nil
  end
end
