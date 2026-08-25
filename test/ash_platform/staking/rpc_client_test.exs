defmodule AshPlatform.Staking.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.BaseRpcStub, as: Stub
  alias AshPlatform.Staking.RpcClient
  alias AshPlatform.WalletActions.{Abi, Envelope}

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @tx_hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)
  @amount 1_500_000_000_000_000_000

  setup do
    Stub.install(:staking_http_client, &call/2)
    :ok
  end

  defp call(data, state) do
    cond do
      data == Abi.encode_read("stake_token") -> Stub.uint(word(Abi.stake_token_address()))
      data == Abi.encode_read("usdc") -> Stub.uint(word(Abi.usdc_address()))
      data == Abi.encode_read("paused") -> Stub.uint(0)
      data == Abi.encode_read("total_staked") -> Stub.uint(Map.get(state, :total_staked, 100))
      data == Abi.encode_supply_denominator() -> Stub.uint(Map.get(state, :denominator, 1_000))
      String.starts_with?(data, "0xdd62ed3e") -> Stub.uint(Map.get(state, :allowance, 0))
      true -> Stub.uint(Map.get(state, :uint, 5))
    end
  end

  defp word(address), do: String.to_integer(String.trim_leading(address, "0x"), 16)

  # One safe block owns the whole page. Nothing may answer from another history,
  # so every read carries that exact block hash and refuses a moved block.
  test "ONE_SAFE_BLOCK: every read of one overview is pinned to the same canonical block" do
    assert {:ok, snapshot} = overview()

    assert snapshot.block_number == 0x20
    assert snapshot.block_hash == Stub.safe_hash()

    assert_received {:rpc, "eth_getBlockByNumber", ["safe", false]}

    blocks = Stub.call_blocks()
    assert Enum.count_until(blocks, 8) == 8
    assert Enum.uniq(blocks) == [%{blockHash: Stub.safe_hash(), requireCanonical: true}]
  end

  test "ONE_SAFE_BLOCK: remaining capacity is the denominator less the total stake, floored at zero" do
    Stub.put(%{denominator: 1_000, total_staked: 100})
    assert {:ok, %{remaining_capacity_raw: "900", supply_denominator_raw: "1000"}} = overview()

    Stub.put(%{denominator: 100, total_staked: 100})
    assert {:ok, %{remaining_capacity_raw: "0"}} = overview()

    # A total above the cap is still no capacity, never a negative one.
    Stub.put(%{denominator: 100, total_staked: 250})
    assert {:ok, %{remaining_capacity_raw: "0"}} = overview()
  end

  # Unavailable evidence is its own outcome and can never read as a balance of
  # nothing, whichever part of the snapshot could not be taken.
  test "ONE_SAFE_BLOCK: a missing, malformed or wrong-chain snapshot fails closed" do
    for {name, state} <- [
          {"no safe tag", %{safe_block: :unavailable}},
          {"header without a hash", %{safe_block: %{"number" => "0x20"}}},
          {"header without a number", %{safe_block: %{"hash" => Stub.safe_hash()}}},
          {"malformed block number",
           %{safe_block: %{"number" => "later", "hash" => Stub.safe_hash()}}},
          {"malformed block hash", %{safe_block: %{"number" => "0x20", "hash" => "0xnope"}}},
          {"wrong chain", %{chain_id: "0x1"}},
          {"unreadable chain id", %{chain_id: :unavailable}}
        ] do
      Stub.put(state)
      assert {:error, _unavailable} = overview(), "#{name} should fail closed"
    end
  end

  test "ONE_SAFE_BLOCK: an unsupported block-pinned call is unavailable, never zero" do
    Application.put_env(:ash_platform, :staking_http_client, Stub.UnsupportedCall)
    assert {:error, :chain_unavailable} = overview()
  after
    Application.put_env(:ash_platform, :staking_http_client, Stub)
  end

  # Four closed outcomes and nothing else. Only the third is success.
  test "FOUR_OUTCOMES: pending, above-safe, reverted, confirmed and unverified" do
    envelope = claim_usdc_envelope()

    put_receipt(nil)
    put_transaction(transaction(envelope))
    assert {:ok, %{outcome: :pending}} = RpcClient.confirm(envelope, @tx_hash)

    # Mined above the safe head: the hash and its state survive untouched.
    put_receipt(receipt("0x21", claim_logs(:usdc, @wallet)))

    assert {:ok, %{outcome: :pending, transaction_hash: @tx_hash}} =
             RpcClient.confirm(envelope, @tx_hash)

    put_receipt(receipt("0x10", [], "0x0"))
    assert {:ok, %{outcome: :reverted}} = RpcClient.confirm(envelope, @tx_hash)

    put_receipt(receipt("0x10", claim_logs(:usdc, @wallet)))
    assert {:ok, %{outcome: :confirmed}} = RpcClient.confirm(envelope, @tx_hash)

    # A safe successful receipt whose logs never recorded this action: terminal,
    # and never success.
    put_receipt(receipt("0x10", []))

    assert {:ok, %{outcome: :unverified, transaction_hash: @tx_hash}} =
             RpcClient.confirm(envelope, @tx_hash)
  end

  # Canonical comes before status: a revert this transaction may still leave is
  # not a revert, exactly as a success it may still leave is not a success.
  test "FOUR_OUTCOMES: a receipt whose block is above safe or no longer canonical stays open" do
    envelope = claim_usdc_envelope()
    put_transaction(transaction(envelope))
    moved = %{"0x10" => %{"number" => "0x10", "hash" => "0x" <> String.duplicate("99", 32)}}

    for {name, status, logs} <- [
          {"success", "0x1", claim_logs(:usdc, @wallet)},
          {"revert", "0x0", []}
        ] do
      put_receipt(receipt("0x21", logs, status))
      Stub.put(%{blocks: %{}})

      assert {:ok, %{outcome: :pending}} = RpcClient.confirm(envelope, @tx_hash),
             "an above-safe #{name} should stay open"

      put_receipt(receipt("0x10", logs, status))
      Stub.put(%{blocks: moved})

      assert {:ok, %{outcome: :pending}} = RpcClient.confirm(envelope, @tx_hash),
             "a reorged #{name} should stay open"

      Stub.put(%{blocks: %{"0x10" => :unavailable}})

      assert {:error, :chain_unavailable} = RpcClient.confirm(envelope, @tx_hash),
             "an unreadable canonical check for a #{name} is unavailable"
    end
  end

  # Each action's own event, decoded against the deployed layout. Every case here
  # is a safe successful receipt, so only the logs decide the outcome.
  test "EVENT_MATRIX: each action confirms on its exact event and nothing else" do
    for {name, envelope, logs, expected} <- [
          {"stake", stake_envelope(), [stake_updated(@wallet, 5, 10)], :confirmed},
          {"stake credits the receiver", stake_envelope(), [stake_updated(@other, 5, 10)],
           :unverified},
          {"stake balance above the global total", stake_envelope(),
           [stake_updated(@wallet, 11, 10)], :unverified},
          {"stake from another contract", stake_envelope(),
           [%{stake_updated(@wallet, 5, 10) | "address" => @other}], :unverified},
          {"stake with the wrong topic", stake_envelope(),
           [put_topic0(stake_updated(@wallet, 5, 10), Abi.event_topic(:approval))], :unverified},
          {"stake with an extra indexed topic", stake_envelope(),
           [add_topic(stake_updated(@wallet, 5, 10))], :unverified},
          {"stake with a short data word", stake_envelope(),
           [%{stake_updated(@wallet, 5, 10) | "data" => Stub.uint(5)}], :unverified},
          {"stake emitted twice", stake_envelope(),
           [stake_updated(@wallet, 5, 10), stake_updated(@wallet, 5, 10)], :unverified},
          {"unstake", unstake_envelope(), [stake_updated(@wallet, 1, 10)], :confirmed},
          {"unstake for another account", unstake_envelope(), [stake_updated(@other, 1, 10)],
           :unverified},
          {"usdc claim", claim_usdc_envelope(), claim_logs(:usdc, @wallet), :confirmed},
          {"usdc claim of nothing", claim_usdc_envelope(),
           [reward_claimed(:usdc, @wallet, 0, @wallet)], :unverified},
          {"usdc claim to another recipient", claim_usdc_envelope(),
           [reward_claimed(:usdc, @wallet, 5, @other)], :unverified},
          {"usdc claim with no event at all", claim_usdc_envelope(), [], :unverified},
          {"regent claim", claim_regent_envelope(), claim_logs(:regent, @wallet), :confirmed},
          {"regent claim using the USDC event", claim_regent_envelope(),
           claim_logs(:usdc, @wallet), :unverified},
          {"compound", compound_envelope(),
           [compounded(@wallet, 5, 20, 100), stake_updated(@wallet, 20, 100)], :confirmed},
          {"compound among unrelated logs", compound_envelope(),
           [unrelated(), compounded(@wallet, 5, 20, 100), stake_updated(@wallet, 20, 100)],
           :confirmed},
          {"compound of nothing", compound_envelope(),
           [compounded(@wallet, 0, 20, 100), stake_updated(@wallet, 20, 100)], :unverified},
          {"compound without its companion", compound_envelope(),
           [compounded(@wallet, 5, 20, 100)], :unverified},
          {"compound whose companion disagrees", compound_envelope(),
           [compounded(@wallet, 5, 20, 100), stake_updated(@wallet, 21, 100)], :unverified}
        ] do
      put_transaction(transaction(envelope))
      put_receipt(receipt("0x10", logs))

      assert {:ok, %{outcome: ^expected}} = RpcClient.confirm(envelope, @tx_hash),
             "#{name} should be #{expected}"
    end
  end

  test "TRANSACTION_IDENTITY: signer, target, calldata, value and hash must all be exact" do
    envelope = claim_usdc_envelope()
    put_receipt(receipt("0x10", claim_logs(:usdc, @wallet)))
    exact = transaction(envelope)

    for {name, transaction, expected} <- [
          {"exact", exact, :confirmed},
          {"wrong signer", %{exact | "from" => @other}, {:error, :transaction_mismatch}},
          {"wrong target", %{exact | "to" => @other}, {:error, :transaction_mismatch}},
          {"wrong calldata", %{exact | "input" => "0xdeadbeef"}, {:error, :transaction_mismatch}},
          {"non-zero value", %{exact | "value" => "0x1"}, {:error, :transaction_mismatch}},
          {"wrong hash", %{exact | "hash" => @approval_hash}, {:error, :transaction_mismatch}},
          {"missing transaction", nil, {:error, :transaction_missing}}
        ] do
      put_transaction(transaction)

      case {expected, RpcClient.confirm(envelope, @tx_hash)} do
        {:confirmed, {:ok, %{outcome: outcome}}} -> assert outcome == :confirmed, name
        {error, result} -> assert result == error, name
      end
    end

    put_transaction(exact)
    put_receipt(%{receipt("0x10", []) | "transactionHash" => @approval_hash})
    assert {:error, :receipt_mismatch} = RpcClient.confirm(envelope, @tx_hash)
  end

  # The chain identity is proved once, by the safe block this outcome is judged
  # against, and never asked for a second time in the same attempt.
  test "ONE_CHAIN_PROOF: confirmation asks for the chain identity exactly once" do
    envelope = claim_usdc_envelope()
    put_transaction(transaction(envelope))
    put_receipt(receipt("0x10", claim_logs(:usdc, @wallet)))

    assert {:ok, %{outcome: :confirmed}} = RpcClient.confirm(envelope, @tx_hash)
    assert chain_id_requests() == 1
  end

  # The approval's own receipt and its own event complete it. The mutable
  # allowance is not consulted here at all.
  test "APPROVAL_EVENT: the exact approval event completes the approval transaction" do
    envelope = stake_envelope()
    token = Abi.stake_token_address()

    put_transaction(%{
      "hash" => @approval_hash,
      "from" => @wallet,
      "to" => token,
      "input" => envelope.approval.data,
      "value" => "0x0"
    })

    Stub.put(%{allowance: 0})
    put_receipt(receipt("0x10", [approval_log(@wallet, Abi.staking_address(), @amount)]))
    assert RpcClient.approval_status(envelope, @approval_hash) == {:ok, :confirmed}

    for {name, logs} <- [
          {"no approval event", []},
          {"wrong owner", [approval_log(@other, Abi.staking_address(), @amount)]},
          {"wrong spender", [approval_log(@wallet, @other, @amount)]},
          {"wrong value", [approval_log(@wallet, Abi.staking_address(), @amount - 1)]},
          {"duplicated approval",
           [
             approval_log(@wallet, Abi.staking_address(), @amount),
             approval_log(@wallet, Abi.staking_address(), @amount)
           ]}
        ] do
      put_receipt(receipt("0x10", logs))

      assert RpcClient.approval_status(envelope, @approval_hash) == {:ok, :unverified},
             "#{name} should be unverified"
    end
  end

  test "APPROVAL_EVENT: confirmation of the stake never requires the allowance to remain" do
    envelope = stake_envelope()
    put_transaction(transaction(envelope))
    put_receipt(receipt("0x10", [stake_updated(@wallet, 5, 10)]))

    # `transferFrom` legitimately spends the allowance, so zero afterwards is the
    # expected state and never a reason to withhold the confirmation.
    Stub.put(%{allowance: 0})
    assert {:ok, %{outcome: :confirmed}} = RpcClient.confirm(envelope, @tx_hash)
    refute_received {:rpc, "eth_call", [%{data: "0xdd62ed3e" <> _rest}, _block]}
  end

  test "FRESH_APPROVAL: the pre-dispatch check requires the exact allowance on a fresh block" do
    envelope = stake_envelope()

    Stub.put(%{allowance: @amount})
    assert RpcClient.approval_current(envelope) == :ok
    assert_received {:rpc, "eth_getBlockByNumber", ["safe", false]}

    for allowance <- [0, @amount - 1, @amount + 1] do
      Stub.put(%{allowance: allowance})
      assert RpcClient.approval_current(envelope) == {:error, :approval_allowance_mismatch}
    end

    assert RpcClient.approval_current(claim_usdc_envelope()) == :ok
  end

  test "transport logs never reveal the provider URL" do
    Application.put_env(:ash_platform, :staking_http_client, Stub.Timeout)

    log = capture_log(fn -> assert {:error, :chain_unavailable} = RpcClient.overview(nil) end)

    assert log =~ "class: :timeout"
    refute log =~ "super-secret"
    refute log =~ "provider.invalid"
  end

  defp overview, do: RpcClient.overview(@wallet)

  defp chain_id_requests(count \\ 0) do
    receive do
      {:rpc, "eth_chainId", _params} -> chain_id_requests(count + 1)
      {:rpc, _method, _params} -> chain_id_requests(count)
    after
      0 -> count
    end
  end

  defp stake_envelope do
    Envelope.new("stake", @wallet, Abi.encode_action("stake", [@amount, @wallet]),
      risk_copy: "Stake REGENT.",
      arguments: %{amount_atomic: Integer.to_string(@amount), receiver: @wallet},
      approval: %{
        token: Abi.stake_token_address(),
        spender: Abi.staking_address(),
        amount: Integer.to_string(@amount),
        data: Abi.encode_erc20("approve", [Abi.staking_address(), @amount]),
        mode: "exact"
      }
    )
  end

  defp unstake_envelope do
    Envelope.new("unstake", @wallet, Abi.encode_action("unstake", [@amount, @wallet]),
      risk_copy: "Unstake REGENT.",
      arguments: %{amount_atomic: Integer.to_string(@amount), recipient: @wallet}
    )
  end

  defp claim_usdc_envelope do
    Envelope.new("claim_usdc", @wallet, Abi.encode_action("claim_usdc", [@wallet]),
      risk_copy: "Claim USDC.",
      arguments: %{recipient: @wallet}
    )
  end

  defp claim_regent_envelope do
    Envelope.new("claim_regent", @wallet, Abi.encode_action("claim_regent", [@wallet]),
      risk_copy: "Claim REGENT.",
      arguments: %{recipient: @wallet}
    )
  end

  defp compound_envelope do
    Envelope.new(
      "claim_and_restake_regent",
      @wallet,
      Abi.encode_action("claim_and_restake_regent", []),
      risk_copy: "Claim and restake REGENT.",
      arguments: %{}
    )
  end

  defp transaction(envelope), do: Stub.transaction(@tx_hash, envelope)

  defp receipt(block_number, logs, status \\ "0x1"),
    do: Stub.receipt(@tx_hash, block_number, logs, status)

  defp claim_logs(:usdc, account), do: [reward_claimed(:usdc, account, 5, account)]
  defp claim_logs(:regent, account), do: [reward_claimed(:regent, account, 5, account)]

  defp stake_updated(account, balance, total) do
    log(Abi.staking_address(), [Abi.event_topic(:stake_updated), Stub.address_topic(account)], [
      balance,
      total
    ])
  end

  defp compounded(account, amount, balance, total) do
    log(
      Abi.staking_address(),
      [Abi.event_topic(:reward_token_compounded), Stub.address_topic(account)],
      [amount, balance, total]
    )
  end

  defp reward_claimed(token, account, amount, recipient) do
    id = if token == :usdc, do: :usdc_reward_claimed, else: :reward_token_claimed

    %{
      "address" => Abi.staking_address(),
      "topics" => [Abi.event_topic(id), Stub.address_topic(account)],
      "data" => "0x" <> Stub.hex_word(amount) <> Stub.address_word(recipient)
    }
  end

  defp approval_log(owner, spender, value) do
    %{
      "address" => Abi.stake_token_address(),
      "topics" => [
        Abi.event_topic(:approval),
        Stub.address_topic(owner),
        Stub.address_topic(spender)
      ],
      "data" => Stub.uint(value)
    }
  end

  defp unrelated do
    %{
      "address" => Abi.usdc_address(),
      "topics" => [Abi.topic0("Transfer(address,address,uint256)"), Stub.address_topic(@wallet)],
      "data" => Stub.uint(1)
    }
  end

  defp log(emitter, topics, words),
    do: %{
      "address" => emitter,
      "topics" => topics,
      "data" => "0x" <> Enum.map_join(words, &Stub.hex_word/1)
    }

  defp put_topic0(log, topic), do: %{log | "topics" => [topic | tl(log["topics"])]}
  defp add_topic(log), do: %{log | "topics" => log["topics"] ++ [Stub.address_topic(@other)]}

  defp put_receipt(receipt),
    do:
      Stub.put(%{
        receipts: %{
          @tx_hash => receipt,
          @approval_hash => receipt && %{receipt | "transactionHash" => @approval_hash}
        }
      })

  defp put_transaction(transaction),
    do:
      Stub.put(%{
        transactions: %{
          @tx_hash => transaction,
          @approval_hash => transaction && %{transaction | "hash" => @approval_hash}
        }
      })
end
