defmodule AshPlatform.Autolaunch.LabPositionRpcClient do
  @moduledoc false

  @key :autolaunch_lab_position_rpc_fixture

  def install(state) do
    previous = Application.get_env(:ash_platform, :autolaunch_lab_http_client)
    Application.put_env(:ash_platform, :autolaunch_lab_http_client, __MODULE__)
    Application.put_env(:ash_platform, @key, state)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:ash_platform, @key)

      if is_nil(previous),
        do: Application.delete_env(:ash_platform, :autolaunch_lab_http_client),
        else: Application.put_env(:ash_platform, :autolaunch_lab_http_client, previous)
    end)
  end

  def put(changes),
    do: Application.put_env(:ash_platform, @key, Map.merge(state(), Map.new(changes)))

  def state, do: Application.fetch_env!(:ash_platform, @key)

  def post(url, options) do
    state = state()
    request = options[:json]
    send(state.test_pid, {:lab_rpc, request.method, request.params})

    if url == state.rpc_url do
      case answer(request.method, request.params, state) do
        {:error, reason} -> {:ok, %{status: 200, body: %{"error" => %{"message" => reason}}}}
        result -> {:ok, %{status: 200, body: %{"result" => result}}}
      end
    else
      {:error, :wrong_endpoint}
    end
  end

  defp answer("eth_chainId", _params, state), do: state.chain_id

  defp answer("eth_getBlockByNumber", ["latest", false], state),
    do: header(state.current_block, state.latest_hash)

  defp answer("eth_getBlockByNumber", [number, false], state),
    do: Map.get(state.blocks, number, header(quantity(number), state.receipt_hash))

  defp answer("eth_getCode", [address, _block], state),
    do: if(address in state.contracts, do: "0x6001", else: "0x")

  defp answer("eth_call", [%{data: data}, _block], state),
    do: Map.get(state.calls, data, {:error, "unexpected call"})

  defp answer("eth_getTransactionReceipt", [hash], state), do: state.receipts[hash]

  defp answer("eth_getTransactionByHash", [hash], state), do: state.transactions[hash]
  defp answer(_method, _params, _state), do: {:error, "unexpected request"}

  defp header(number, hash),
    do: %{"number" => hex(number), "hash" => hash}

  defp quantity("0x" <> value), do: String.to_integer(value, 16)
  defp hex(value), do: "0x" <> String.downcase(Integer.to_string(value, 16))
end

defmodule AshPlatform.Autolaunch.LabPositionActionsTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.Human
  alias AshPlatform.Actors.System, as: SystemActor

  alias AshPlatform.{Accounts, Autolaunch, Formation}

  alias AshPlatform.Autolaunch.{
    Auction,
    Bid,
    Lab,
    LabAbi,
    LabBidChainClient,
    LabLaunchChainClient,
    LabPositionRpcClient,
    LabProjection,
    LaunchChainClient,
    LaunchJob,
    Subject,
    Token
  }

  alias AshPlatform.WalletActions.Envelope

  @domain Autolaunch
  @system %SystemActor{}
  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x1212121212121212121212121212121212121212"
  @factory "0x2222222222222222222222222222222222222222"
  @strategy "0x3333333333333333333333333333333333333333"
  @hook "0x4444444444444444444444444444444444444444"
  @regent "0x5555555555555555555555555555555555555555"
  @permit2 "0x6666666666666666666666666666666666666666"
  @auction "0x7777777777777777777777777777777777777777"
  @subject "0x8888888888888888888888888888888888888888"
  @escrow "0x9999999999999999999999999999999999999999"
  @treasury "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @splitter "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  @receiver "0xcccccccccccccccccccccccccccccccccccccccc"
  @block_hash "0x" <> String.duplicate("ab", 32)
  @receipt_hash "0x" <> String.duplicate("cd", 32)
  @q96 79_228_162_514_264_337_593_543_950_336
  @unit Integer.pow(10, 18)
  @uint256_max Integer.pow(2, 256) - 1

  setup context do
    path = write_config!(context)
    previous_enabled = Application.get_env(:ash_platform, :autolaunch_lab_enabled)
    previous_path = Application.get_env(:ash_platform, :autolaunch_lab_config_path)
    Application.put_env(:ash_platform, :autolaunch_lab_enabled, true)
    Application.put_env(:ash_platform, :autolaunch_lab_config_path, path)

    on_exit(fn ->
      restore(:autolaunch_lab_enabled, previous_enabled)
      restore(:autolaunch_lab_config_path, previous_path)
      File.rm(path)
    end)

    config = Lab.current!()
    LabPositionRpcClient.install(rpc_state(config))
    actor = actor_fixture()
    records = project_records!()
    {:ok, Map.merge(actor, records) |> Map.put(:config_path, path)}
  end

  test "full exit, claim, and migration verify exact receipts and project once", context do
    assert {:ok, position} =
             Autolaunch.lab_position(context.auction.id, @wallet, context.opts)

    assert position.status == :exit_ready
    assert position.actions == %{exit: true, claim: false, migrate: false}

    assert {:ok, %{operation: exit}} =
             Autolaunch.prepare_lab_position(context.bid.bid_id, @wallet, :exit, context.opts)

    assert exit.envelope["chain_id"] == 31_337
    assert exit.envelope["arguments"]["token_name"] == "Local Regent"
    assert exit.envelope["arguments"]["token_symbol"] == "LOCAL"
    assert Envelope.valid?(exit.envelope, resource: "autolaunch_lab_position", chain_id: 31_337)

    assert {:ok, %{operation: exit}} =
             Autolaunch.claim_lab_position_dispatch(exit, @wallet, context.opts)

    exit_hash = transaction_hash(1)

    set_receipt(
      exit,
      exit_hash,
      [event("BidExited(uint256,address,uint256,uint256)", @auction, [9, @wallet], [50, 10])],
      bid_words: bid_words(exited_block: 160, tokens_filled: 50)
    )

    assert {:ok, %{operation: %{state: :confirmed}}} =
             Autolaunch.verify_lab_position(exit, exit_hash, context.opts)

    bid = bid!()
    assert bid.status == "exited"
    assert bid.exited_at

    LabPositionRpcClient.put(
      current_block: 175,
      calls: calls(Lab.current!(), bid_words: bid_words(exited_block: 160, tokens_filled: 50))
    )

    assert {:ok, %{operation: claim}} =
             Autolaunch.prepare_lab_position(bid.bid_id, @wallet, :claim, context.opts)

    assert {:ok, %{operation: claim}} =
             Autolaunch.claim_lab_position_dispatch(claim, @wallet, context.opts)

    claim_hash = transaction_hash(2)

    set_receipt(
      claim,
      claim_hash,
      [event("TokensClaimed(uint256,address,uint256)", @auction, [9, @wallet], [50])],
      bid_words: bid_words(exited_block: 160, tokens_filled: 0)
    )

    assert {:ok, %{operation: %{state: :confirmed}}} =
             Autolaunch.verify_lab_position(claim, claim_hash, context.opts)

    bid = bid!()
    assert bid.status == "claimed"
    assert bid.claimed_at

    migrated_distribution = distribution(lifecycle: 2)

    LabPositionRpcClient.put(
      current_block: 200,
      calls:
        calls(Lab.current!(),
          bid_words: bid_words(exited_block: 160, tokens_filled: 0),
          distribution: distribution(lifecycle: 1)
        )
    )

    assert {:ok, %{operation: migrate}} =
             Autolaunch.prepare_lab_position(bid.bid_id, @wallet, :migrate, context.opts)

    assert [%{"to" => @strategy, "data" => migration_data}] =
             migrate.envelope["arguments"]["steps"]

    assert migration_data ==
             LabAbi.encode(Lab.current!().abis["strategy"], "migrate(address)", [@auction])

    refute migration_data ==
             LabAbi.encode(Lab.current!().abis["strategy"], "migrate(address)", [@subject])

    assert {:ok, %{operation: migrate}} =
             Autolaunch.claim_lab_position_dispatch(migrate, @wallet, context.opts)

    migrate_hash = transaction_hash(3)

    migration_log =
      event(
        "LaunchGraduated(address,address,bytes32,address,address,uint160,uint256,uint128,uint128)",
        @strategy,
        [@auction, @subject, Enum.at(migrated_distribution, 16)],
        [
          @splitter,
          @receiver,
          Enum.at(migrated_distribution, 9),
          Enum.at(migrated_distribution, 17),
          Enum.at(migrated_distribution, 7),
          Enum.at(migrated_distribution, 8)
        ]
      )

    set_receipt(migrate, migrate_hash, [migration_log], distribution: migrated_distribution)

    assert {:ok, %{operation: %{state: :confirmed}}} =
             Autolaunch.verify_lab_position(migrate, migrate_hash, context.opts)

    assert bid!().status == "claimed"
    assert auction!().state == :graduated
    assert subject!().splitter_address == @splitter
    assert launch!().status == "complete"
    assert token!().symbol == "LOCAL"

    assert {:ok, %{operation: %{state: :confirmed}}} =
             Autolaunch.verify_lab_position(migrate, migrate_hash, context.opts)

    assert length(all(Token, :read)) == 1
  end

  test "launch preparation uses the exact local config and bypasses Base treasury evidence",
       context do
    draft = AshPlatform.LaunchFixture.draft!(context.actor)

    assert {:ok, %{operation: operation}} =
             Autolaunch.prepare_launch(draft.id, @wallet, context.opts)

    assert operation.envelope["chain_id"] == 31_337

    assert operation.envelope["metadata"]["lab"] ==
             Lab.binding(Lab.current!(), [:factory, :strategy, :hook, :regent])

    assert operation.envelope["arguments"]["treasury_security"] == %{
             "mode" => "local_lab",
             "address" => String.downcase(draft.treasury),
             "path" => Atom.to_string(draft.treasury_path)
           }

    assert Enum.map(operation.envelope["arguments"]["steps"], & &1["step"]) == [
             "approval",
             "launch"
           ]

    assert {:ok, %{operation: dispatched}} =
             Autolaunch.claim_launch_dispatch(operation.action_id, @wallet, context.opts)

    assert dispatched.state == :dispatched
    assert dispatched.step == :approval
  end

  test "the durable launch sequence verifies its approval and exact LaunchCreated readback",
       context do
    assert LaunchChainClient.module() == LabLaunchChainClient

    draft = AshPlatform.LaunchFixture.draft!(context.actor)

    assert {:ok, %{operation: operation}} =
             Autolaunch.prepare_launch(draft.id, @wallet, context.opts)

    fee = String.to_integer(operation.envelope["arguments"]["expected_launch_fee_atomic"])

    assert {:ok, %{operation: approval}} =
             Autolaunch.claim_launch_dispatch(operation.action_id, @wallet, context.opts)

    approval_hash = transaction_hash(11)

    set_receipt(
      approval,
      approval_hash,
      [event("Approval(address,address,uint256)", @regent, [@wallet, @factory], [fee])],
      token_factory_allowance: fee
    )

    assert {:ok, %{outcome: :confirmed}} =
             LabLaunchChainClient.verify(approval.envelope, :approval, approval_hash)

    assert {:ok, %{operation: submitted}} =
             Autolaunch.bind_launch_hash(
               approval.action_id,
               :approval,
               approval_hash,
               context.opts
             )

    assert submitted.state == :submitted

    assert {:ok, %{outcome: :confirmed}} =
             LaunchChainClient.module().verify(
               submitted.envelope,
               :approval,
               approval_hash
             )

    assert {:ok, %{operation: launch}} =
             Autolaunch.verify_launch_step(approval.action_id, context.opts)

    assert launch.state == :prepared
    assert launch.step == :launch

    assert {:ok, %{operation: launch}} =
             Autolaunch.claim_launch_dispatch(launch.action_id, @wallet, context.opts)

    launch_hash = transaction_hash(12)

    required_raise =
      String.to_integer(launch.envelope["arguments"]["required_regent_raised_atomic"])

    treasury = launch.envelope["arguments"]["treasury"]

    set_receipt(
      launch,
      launch_hash,
      [
        event(
          "LaunchCreated(uint256,address,address,address,address,address,uint128,uint64,uint64)",
          @factory,
          [17, @wallet, @subject],
          [@auction, @escrow, treasury, required_raise, 100, 150]
        )
      ],
      token_factory_allowance: fee,
      launch_id: 17,
      launch_treasury: treasury
    )

    assert {:ok, %{outcome: :confirmed, result: %{"launch_id" => "17"}}} =
             LabLaunchChainClient.verify(launch.envelope, :launch, launch_hash)

    assert {:ok, %{operation: _submitted}} =
             Autolaunch.bind_launch_hash(launch.action_id, :launch, launch_hash, context.opts)

    assert {:ok, %{operation: verified}} =
             Autolaunch.verify_launch_step(launch.action_id, context.opts)

    assert verified.state == :chain_verified
    assert verified.result["launch_id"] == "17"
    assert verified.result["auction"] == @auction
    assert auction!().treasury_address == treasury
  end

  test "bid preparation encodes only the exact five-argument local overload", context do
    assert {:ok, %{operation: operation}} =
             Autolaunch.prepare_bid(context.auction.id, @wallet, "10", "2.5", context.opts)

    config = Lab.current!()

    assert operation.envelope["chain_id"] == 31_337
    assert operation.envelope["metadata"]["lab"] == Lab.binding(config, [:regent, :permit2])
    assert operation.envelope["arguments"]["permit2"] == @permit2

    assert operation.envelope["arguments"]["treasury_security"] == %{
             "mode" => "local_lab",
             "auction_id" => context.auction.id,
             "auction_address" => @auction,
             "address" => @treasury
           }

    assert Enum.map(operation.envelope["arguments"]["steps"], & &1["step"]) == [
             "token_approval",
             "permit2_approval",
             "bid"
           ]

    assert String.starts_with?(
             operation.envelope["data"],
             LabAbi.selector("submitBid(uint256,uint128,address,uint256,bytes)")
           )

    assert {:ok, %{operation: %{state: :dispatched}}} =
             Autolaunch.claim_bid_dispatch(operation.action_id, context.opts)
  end

  test "the durable bid sequence verifies both approvals and the exact five-argument bid",
       context do
    assert {:ok, %{operation: operation}} =
             Autolaunch.prepare_bid(context.auction.id, @wallet, "10", "2.5", context.opts)

    amount = String.to_integer(operation.envelope["arguments"]["amount_atomic"])
    max_price = String.to_integer(operation.envelope["arguments"]["max_price_q96"])

    assert {:ok, %{operation: token_approval}} =
             Autolaunch.claim_bid_dispatch(operation.action_id, context.opts)

    token_hash = transaction_hash(21)

    set_receipt(
      token_approval,
      token_hash,
      [event("Approval(address,address,uint256)", @regent, [@wallet, @permit2], [amount])],
      token_permit2_allowance: amount
    )

    assert {:ok, %{outcome: :confirmed}} =
             LabBidChainClient.verify(token_approval.envelope, :token_approval, token_hash)

    assert {:ok, %{operation: _submitted}} =
             Autolaunch.bind_bid_hash(
               token_approval.action_id,
               :token_approval,
               token_hash,
               context.opts
             )

    assert {:ok, %{operation: permit2_approval}} =
             Autolaunch.verify_bid_step(token_approval.action_id, context.opts)

    assert permit2_approval.state == :prepared
    assert permit2_approval.step == :permit2_approval

    assert {:ok, %{operation: permit2_approval}} =
             Autolaunch.claim_bid_dispatch(permit2_approval.action_id, context.opts)

    permit2_step =
      Enum.find(
        permit2_approval.envelope["arguments"]["steps"],
        &(&1["step"] == "permit2_approval")
      )

    expiration = String.to_integer(permit2_step["expiration"])
    permit2_hash = transaction_hash(22)

    set_receipt(
      permit2_approval,
      permit2_hash,
      [
        event(
          "Approval(address,address,address,uint160,uint48)",
          @permit2,
          [@wallet, @regent, @auction],
          [amount, expiration]
        )
      ],
      token_permit2_allowance: amount,
      permit2_amount: amount,
      permit2_expiration: expiration
    )

    assert {:ok, %{outcome: :confirmed}} =
             LabBidChainClient.verify(
               permit2_approval.envelope,
               :permit2_approval,
               permit2_hash
             )

    assert {:ok, %{operation: _submitted}} =
             Autolaunch.bind_bid_hash(
               permit2_approval.action_id,
               :permit2_approval,
               permit2_hash,
               context.opts
             )

    assert {:ok, %{operation: bid}} =
             Autolaunch.verify_bid_step(permit2_approval.action_id, context.opts)

    assert bid.state == :prepared
    assert bid.step == :bid

    assert {:ok, %{operation: bid}} =
             Autolaunch.claim_bid_dispatch(bid.action_id, context.opts)

    bid_hash = transaction_hash(23)

    set_receipt(
      bid,
      bid_hash,
      [
        event(
          "BidSubmitted(uint256,address,uint256,uint128)",
          @auction,
          [10, @wallet],
          [max_price, amount]
        )
      ],
      token_permit2_allowance: amount,
      permit2_amount: amount,
      permit2_expiration: expiration
    )

    assert {:ok, %{outcome: :confirmed, onchain_bid_id: "10"}} =
             LabBidChainClient.verify(bid.envelope, :bid, bid_hash)

    assert {:ok, %{operation: _submitted}} =
             Autolaunch.bind_bid_hash(bid.action_id, :bid, bid_hash, context.opts)

    assert {:ok, %{operation: confirmed}} =
             Autolaunch.verify_bid_step(bid.action_id, context.opts)

    assert confirmed.state == :confirmed
    assert confirmed.onchain_bid_id == "10"

    projected =
      all(Bid, :mine)
      |> Enum.find(&(&1.onchain_bid_id == "10"))

    assert projected.owner_address == @wallet
    assert projected.auction_address == @auction
  end

  test "replacement config invalidates prepared work even though both nodes use chain 31337",
       context do
    assert {:ok, %{operation: operation}} =
             Autolaunch.prepare_lab_position(context.bid.bid_id, @wallet, :exit, context.opts)

    original = File.read!(context.config_path) |> Jason.decode!()

    changed =
      put_in(original, ["addresses", "strategy"], "0xdddddddddddddddddddddddddddddddddddddddd")

    File.write!(context.config_path, Jason.encode!(changed))

    assert {:error, :lab_config_changed} =
             Autolaunch.claim_lab_position_dispatch(operation, @wallet, context.opts)

    File.write!(context.config_path, Jason.encode!(original))

    assert {:ok, %{operation: %{state: :dispatched}}} =
             Autolaunch.claim_lab_position_dispatch(operation, @wallet, context.opts)
  end

  test "repeated preparations remain independent wallet actions", context do
    assert {:ok, %{operation: first}} =
             Autolaunch.prepare_lab_position(context.bid.bid_id, @wallet, :exit, context.opts)

    assert {:ok, %{operation: second}} =
             Autolaunch.prepare_lab_position(context.bid.bid_id, @wallet, :exit, context.opts)

    refute first.action_id == second.action_id
    assert first.state == :prepared
    assert second.state == :prepared

    assert {:ok, %{operation: %{state: :dispatched}}} =
             Autolaunch.claim_lab_position_dispatch(first, @wallet, context.opts)

    assert {:ok, %{operation: %{state: :dispatched}}} =
             Autolaunch.claim_lab_position_dispatch(second, @wallet, context.opts)
  end

  test "a partially filled bid and contradictory receipt fail closed", context do
    LabPositionRpcClient.put(
      calls:
        calls(Lab.current!(),
          bid_words: bid_words(max_price: @q96, tokens_filled: 50),
          clearing_price: 2 * @q96
        )
    )

    assert {:error, :partial_fill_unsupported} =
             Autolaunch.prepare_lab_position(context.bid.bid_id, @wallet, :exit, context.opts)

    LabPositionRpcClient.put(calls: calls(Lab.current!()))

    assert {:ok, %{operation: operation}} =
             Autolaunch.prepare_lab_position(context.bid.bid_id, @wallet, :exit, context.opts)

    assert {:ok, %{operation: operation}} =
             Autolaunch.claim_lab_position_dispatch(operation, @wallet, context.opts)

    hash = transaction_hash(4)

    set_receipt(
      operation,
      hash,
      [event("BidExited(uint256,address,uint256,uint256)", @auction, [9, @other], [50, 10])],
      bid_words: bid_words(exited_block: 160, tokens_filled: 50)
    )

    assert {:ok, %{operation: %{state: :unverified}}} =
             Autolaunch.verify_lab_position(operation, hash, context.opts)

    assert bid!().status == "active"
  end

  test "local auction and subject pages label the lab and never create Base links", context do
    conn = init_test_session(context.conn, %{human_account_id: context.account.id})

    {:ok, auction_view, _html} =
      live(conn, "/autolaunch/auctions/#{context.auction.id}")

    render_async(auction_view)

    assert has_element?(
             auction_view,
             "#autolaunch-auction-detail",
             "Local Base fork · test assets · no mainnet value"
           )

    assert has_element?(auction_view, "#autolaunch-lab-position")

    render_hook(element(auction_view, "#autolaunch-bid"), "bid_active_wallet", %{
      "address" => @wallet
    })

    auction_view
    |> form("#autolaunch-bid-form", %{amount: "10", max_price: "2.5"})
    |> render_submit()

    assert_push_event(auction_view, "autolaunch-bid:operation", %{action_id: bid_action_id})

    render_hook(element(auction_view, "#autolaunch-bid"), "sign_bid_step", %{
      "action-id" => bid_action_id
    })

    assert_push_event(auction_view, "autolaunch-bid:send", %{
      action_id: ^bid_action_id,
      step: "token_approval"
    })

    local_hash = transaction_hash(31)

    render_hook(element(auction_view, "#autolaunch-bid"), "bid_submitted", %{
      "action_id" => bid_action_id,
      "step" => "token_approval",
      "transaction_hash" => local_hash
    })

    assert has_element?(
             auction_view,
             "#autolaunch-bid [data-local-transaction-hash]",
             short_hash(local_hash)
           )

    refute has_element?(auction_view, "#autolaunch-bid a[href*='basescan.org']")

    subject = subject!()
    {:ok, subject_view, _html} = live(conn, "/autolaunch/subjects/#{subject.subject_id}")
    render_async(subject_view)

    assert has_element?(subject_view, "#autolaunch-subject-detail dt", "Chain")
    assert has_element?(subject_view, "#autolaunch-subject-detail dd", "31337")
    refute has_element?(subject_view, "#autolaunch-subject-wallet")
  end

  test "local launch and position hashes remain plain text", context do
    conn = init_test_session(context.conn, %{human_account_id: context.account.id})
    draft = AshPlatform.LaunchFixture.draft!(context.actor)
    launch_card = "#autolaunch-launch-wallet-#{draft.id}"

    {:ok, launch_view, _html} = live(conn, "/autolaunch/create")
    render_async(launch_view)

    render_hook(element(launch_view, launch_card), "launch_active_wallet", %{
      "address" => @wallet
    })

    launch_view
    |> element("#{launch_card} button[phx-click='review_launch']")
    |> render_click()

    assert_push_event(launch_view, "autolaunch-launch:operation", %{
      action_id: launch_action_id
    })

    render_hook(element(launch_view, launch_card), "sign_launch_step", %{
      "action-id" => launch_action_id
    })

    assert_push_event(launch_view, "autolaunch-launch:send", %{
      action_id: ^launch_action_id,
      step: "approval"
    })

    launch_hash = transaction_hash(32)

    render_hook(element(launch_view, launch_card), "launch_submitted", %{
      "action_id" => launch_action_id,
      "step" => "approval",
      "transaction_hash" => launch_hash
    })

    assert has_element?(
             launch_view,
             "#{launch_card} [data-local-transaction-hash]",
             short_hash(launch_hash)
           )

    refute has_element?(launch_view, "#{launch_card} a[href*='basescan.org']")

    {:ok, position_view, _html} =
      live(conn, "/autolaunch/auctions/#{context.auction.id}")

    render_async(position_view)

    render_hook(
      element(position_view, "#autolaunch-lab-position"),
      "lab_position_active_wallet",
      %{"address" => @wallet}
    )

    render_hook(
      element(position_view, "#autolaunch-lab-position"),
      "prepare_lab_position",
      %{"address" => @wallet, "kind" => "exit"}
    )

    assert_push_event(position_view, "autolaunch-lab-position:operation", %{
      action_id: position_action_id
    })

    render_hook(
      element(position_view, "#autolaunch-lab-position"),
      "sign_lab_position_step",
      %{"action-id" => position_action_id}
    )

    assert_push_event(position_view, "autolaunch-lab-position:send", %{
      action_id: ^position_action_id,
      step: "exit"
    })

    position_hash = transaction_hash(33)

    render_hook(
      element(position_view, "#autolaunch-lab-position"),
      "lab_position_submitted",
      %{
        "action_id" => position_action_id,
        "step" => "exit",
        "transaction_hash" => position_hash
      }
    )

    assert has_element?(
             position_view,
             "#autolaunch-lab-position [data-local-transaction-hash]",
             short_hash(position_hash)
           )

    refute has_element?(position_view, "#autolaunch-lab-position a[href*='basescan.org']")
  end

  defp actor_fixture do
    unique = System.unique_integer([:positive])

    account =
      Accounts.register_verified!("did:privy:lab-position-#{unique}", @wallet, [@wallet],
        actor: @system
      )

    {:ok, :bind, claim} = SessionAuthority.sign_in(SessionAuthority.bootstrap(), account.id)
    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("lab-position-#{unique}", "Local Regent #{unique}", actor: actor)

    %{
      account: account,
      actor: actor,
      opts: [
        actor: actor,
        context: %{session_lease: %{lineage: claim.lineage, account_id: account.id}}
      ]
    }
  end

  defp project_records! do
    launch_operation = %{
      envelope: %{
        "chain_id" => 31_337,
        "expected_signer" => @wallet,
        "metadata" => %{
          "lab" => %{
            "rpc_url" => "http://127.0.0.1:49713",
            "chain_id" => 31_337,
            "addresses" => %{"hook" => @hook}
          }
        },
        "arguments" => %{
          "name" => "Local Regent",
          "symbol" => "LOCAL",
          "description" => "A local fork launch.",
          "regent" => @regent,
          "factory" => @factory
        }
      }
    }

    launch_result = %{
      "launch_id" => "17",
      "subject" => @subject,
      "auction" => @auction,
      "escrow" => @escrow,
      "treasury" => @treasury,
      "start_block" => "100",
      "end_block" => "150"
    }

    :ok = LabProjection.project_launch(launch_operation, launch_result)
    auction_id = LabProjection.auction_id(@auction)

    bid_operation = %{
      envelope: %{
        "chain_id" => 31_337,
        "expected_signer" => @wallet,
        "to" => @auction,
        "metadata" => %{
          "lab" => %{
            "rpc_url" => "http://127.0.0.1:49713",
            "chain_id" => 31_337,
            "addresses" => %{"regent" => @regent}
          }
        },
        "arguments" => %{
          "auction_id" => auction_id,
          "amount" => "100",
          "max_price" => "3"
        }
      }
    }

    :ok =
      LabProjection.project_bid(bid_operation, %{
        "onchain_bid_id" => "9",
        "current_clearing_price" => "2"
      })

    %{auction: auction!(), bid: bid!()}
  end

  defp rpc_state(config) do
    %{
      test_pid: self(),
      rpc_url: config.rpc_url,
      chain_id: "0x7a69",
      current_block: 160,
      latest_hash: @block_hash,
      receipt_hash: @receipt_hash,
      blocks: %{},
      contracts: Map.values(config.addresses) ++ [@auction],
      calls: calls(config),
      receipts: %{},
      transactions: %{}
    }
  end

  defp calls(config, overrides \\ []) do
    bid_words = Keyword.get(overrides, :bid_words, bid_words())
    distribution = Keyword.get(overrides, :distribution, distribution())
    clearing_price = Keyword.get(overrides, :clearing_price, 2 * @q96)
    token_factory_allowance = Keyword.get(overrides, :token_factory_allowance, 0)
    token_permit2_allowance = Keyword.get(overrides, :token_permit2_allowance, 0)
    permit2_amount = Keyword.get(overrides, :permit2_amount, 0)
    permit2_expiration = Keyword.get(overrides, :permit2_expiration, 0)
    launch_id = Keyword.get(overrides, :launch_id, 17)
    launch_treasury = Keyword.get(overrides, :launch_treasury, @treasury)

    position_calls = %{
      LabAbi.encode(config.abis["auction"], "bids(uint256)", [9]) => words(bid_words),
      LabAbi.encode(config.abis["auction"], "startBlock()", []) => words([100]),
      LabAbi.encode(config.abis["auction"], "endBlock()", []) => words([150]),
      LabAbi.encode(config.abis["auction"], "claimBlock()", []) => words([170]),
      LabAbi.encode(config.abis["auction"], "isGraduated()", []) => words([1]),
      LabAbi.encode(config.abis["auction"], "clearingPrice()", []) => words([clearing_price]),
      LabAbi.encode(config.abis["strategy"], "distribution(address)", [@auction]) =>
        words(distribution)
    }

    launch_terms = AshPlatform.LaunchFixture.terms()

    lab_calls = %{
      LabAbi.encode(config.abis["factory"], "launchFee()", []) => words([1_000_000 * @unit]),
      LabAbi.encode(config.abis["factory"], "launchesPaused()", []) => words([0]),
      LabAbi.encode(config.abis["factory"], "strategy()", []) =>
        words([address_integer(@strategy)]),
      LabAbi.encode(config.abis["strategy"], "factory()", []) =>
        words([address_integer(@factory)]),
      LabAbi.encode(config.abis["strategy"], "hook()", []) => words([address_integer(@hook)]),
      LabAbi.encode(config.abis["strategy"], "START_DELAY_BLOCKS()", []) =>
        words([launch_terms.start_delay_blocks]),
      LabAbi.encode(config.abis["strategy"], "AUCTION_DURATION_BLOCKS()", []) =>
        words([launch_terms.auction_duration_blocks]),
      LabAbi.encode(config.abis["strategy"], "CLAIM_DELAY_BLOCKS()", []) =>
        words([launch_terms.claim_delay_blocks]),
      LabAbi.encode(config.abis["strategy"], "MIGRATION_DELAY_BLOCKS()", []) =>
        words([launch_terms.migration_delay_blocks]),
      LabAbi.encode(config.abis["strategy"], "FLOOR_PRICE_Q96()", []) =>
        words([launch_terms.floor_price_q96]),
      LabAbi.encode(config.abis["strategy"], "BID_TICK_Q96()", []) =>
        words([launch_terms.bid_tick_q96]),
      LabAbi.encode(config.abis["strategy"], "AUCTION_ALLOCATION()", []) =>
        words([launch_terms.auction_allocation]),
      LabAbi.encode(config.abis["strategy"], "RESERVE_ALLOCATION()", []) =>
        words([launch_terms.reserve_allocation]),
      LabAbi.encode(config.abis["strategy"], "PENDING_ALLOCATION()", []) =>
        words([launch_terms.pending_allocation]),
      LabAbi.encode(config.abis["strategy"], "POOL_FEE()", []) => words([launch_terms.pool_fee]),
      LabAbi.encode(config.abis["strategy"], "POOL_TICK_SPACING()", []) =>
        words([launch_terms.pool_tick_spacing]),
      LabAbi.encode(config.abis["strategy"], "MAX_REACHABLE_RAISE()", []) =>
        words([launch_terms.max_reachable_raise]),
      LabAbi.encode(config.abis["token"], "balanceOf(address)", [@wallet]) =>
        words([10_000_000 * @unit]),
      LabAbi.encode(config.abis["token"], "allowance(address,address)", [@wallet, @factory]) =>
        words([token_factory_allowance]),
      LabAbi.encode(config.abis["token"], "allowance(address,address)", [@wallet, @permit2]) =>
        words([token_permit2_allowance]),
      LabAbi.encode(config.abis["factory"], "launches(uint256)", [launch_id]) =>
        words([
          address_integer(@wallet),
          address_integer(@subject),
          address_integer(@auction),
          address_integer(@escrow),
          address_integer(launch_treasury)
        ]),
      LabAbi.encode(config.abis["factory"], "launchIdOfSubject(address)", [@subject]) =>
        words([launch_id]),
      LabAbi.encode(config.abis["auction"], "currency()", []) =>
        words([address_integer(@regent)]),
      LabAbi.encode(config.abis["permit2"], "allowance(address,address,address)", [
        @wallet,
        @regent,
        @auction
      ]) => words([permit2_amount, permit2_expiration, 0]),
      LabAbi.encode(config.abis["auction"], "floorPrice()", []) => words([@q96]),
      LabAbi.encode(config.abis["auction"], "ticks(uint256)", [@q96]) => words([@uint256_max, 0])
    }

    Map.merge(lab_calls, position_calls)
  end

  defp bid_words(overrides \\ []) do
    [
      100,
      0,
      Keyword.get(overrides, :exited_block, 0),
      Keyword.get(overrides, :max_price, 3 * @q96),
      address_integer(@wallet),
      100,
      Keyword.get(overrides, :tokens_filled, 50)
    ]
  end

  defp distribution(overrides \\ []) do
    [
      Keyword.get(overrides, :lifecycle, 1),
      100,
      150,
      170,
      180,
      0,
      10,
      20,
      30,
      40,
      0,
      address_integer(@subject),
      0,
      address_integer(@treasury),
      address_integer(@splitter),
      address_integer(@receiver),
      50,
      60
    ]
  end

  defp set_receipt(operation, hash, logs, overrides) do
    config = Lab.current!()
    state = LabPositionRpcClient.state()
    block_number = 160

    calls = calls(config, overrides)
    step_name = Map.get(operation, :step) || Map.get(operation, :kind)

    step =
      Enum.find(
        operation.envelope["arguments"]["steps"],
        &(&1["step"] == Atom.to_string(step_name))
      )

    receipt = %{
      "status" => "0x1",
      "blockNumber" => hex(block_number),
      "blockHash" => @receipt_hash,
      "transactionHash" => hash,
      "logs" => logs
    }

    transaction = %{
      "hash" => hash,
      "from" => operation.signer,
      "to" => step["to"],
      "input" => step["data"],
      "value" => "0x0"
    }

    LabPositionRpcClient.put(
      calls: calls,
      blocks:
        Map.put(state.blocks, hex(block_number), %{
          "number" => hex(block_number),
          "hash" => @receipt_hash
        }),
      receipts: Map.put(state.receipts, hash, receipt),
      transactions: Map.put(state.transactions, hash, transaction)
    )
  end

  defp event(signature, emitter, indexed, data) do
    %{
      "address" => emitter,
      "topics" => [LabAbi.topic(signature) | Enum.map(indexed, &topic/1)],
      "data" => "0x" <> Enum.map_join(data, &word/1),
      "blockHash" => @receipt_hash
    }
  end

  defp topic(value), do: "0x" <> word(value)
  defp word("0x" <> address), do: String.pad_leading(String.downcase(address), 64, "0")

  defp word(value) when is_integer(value),
    do: value |> Integer.to_string(16) |> String.pad_leading(64, "0")

  defp words(values), do: "0x" <> Enum.map_join(values, &word/1)
  defp address_integer(address), do: address |> String.trim_leading("0x") |> String.to_integer(16)

  defp transaction_hash(value),
    do:
      "0x" <>
        (value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0"))

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"

  defp hex(value), do: "0x" <> String.downcase(Integer.to_string(value, 16))

  defp auction!, do: one(Auction, :read)
  defp bid!, do: one(Bid, :mine)
  defp subject!, do: one(Subject, :read)
  defp launch!, do: one(LaunchJob, :read)
  defp token!, do: one(Token, :read)

  defp one(resource, action) do
    case all(resource, action) do
      [record] -> record
      records -> flunk("expected one #{inspect(resource)}, got #{length(records)}")
    end
  end

  defp all(resource, action) do
    # Position projection tests inspect raw stored rows with the trusted System actor.
    resource
    |> Ash.Query.for_read(action, %{}, domain: @domain, actor: @system, authorize?: false)
    |> Ash.read!(domain: @domain)
  end

  defp write_config!(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "position-lab-#{context.test |> :erlang.phash2() |> Integer.to_string()}.json"
      )

    address_keys = ~w(
      cca_factory escrow_implementation factory governance_safe hook permit2 pool_manager
      position_manager receiver_implementation regent splitter_implementation strategy
      uerc20_factory
    )

    known = %{
      "factory" => @factory,
      "strategy" => @strategy,
      "hook" => @hook,
      "regent" => @regent,
      "permit2" => @permit2
    }

    addresses =
      address_keys
      |> Enum.with_index(1)
      |> Map.new(fn {key, index} ->
        {key,
         Map.get(known, key, "0x" <> String.pad_leading(Integer.to_string(index, 16), 40, "0"))}
      end)

    abis =
      ~w(auction escrow factory hook permit2 receiver splitter strategy token)
      |> Map.new(fn name ->
        entries =
          LabAbi.requirements()
          |> Map.get(name, [])
          |> Enum.map(&abi_entry/1)

        {name, if(entries == [], do: [abi_entry("placeholder()")], else: entries)}
      end)

    File.write!(
      path,
      Jason.encode!(%{
        "rpc_url" => "http://127.0.0.1:49713",
        "chain_id" => 31_337,
        "addresses" => addresses,
        "abis" => abis
      })
    )

    path
  end

  defp abi_entry({:f, {signature, mutability, outputs}}) do
    {name, inputs} = signature_parts(signature)

    %{
      "type" => "function",
      "name" => name,
      "inputs" => abi_types(inputs),
      "outputs" => Enum.flat_map(outputs, &abi_types/1),
      "stateMutability" => mutability
    }
  end

  defp abi_entry({:e, {signature, indexed}}) do
    {name, inputs} = signature_parts(signature)

    inputs =
      inputs
      |> abi_types()
      |> Enum.zip(indexed)
      |> Enum.map(fn {input, indexed?} -> Map.put(input, "indexed", indexed?) end)

    %{"type" => "event", "name" => name, "inputs" => inputs, "anonymous" => false}
  end

  defp abi_entry(signature) when is_binary(signature),
    do: abi_entry({:f, {signature, "nonpayable", []}})

  defp signature_parts(signature) do
    [name, inputs] =
      Regex.run(~r/\A([^()]+)\((.*)\)\z/, signature, capture: :all_but_first)

    {name, inputs}
  end

  defp abi_types(""), do: []

  defp abi_types(arguments) do
    arguments
    |> split_types()
    |> Enum.map(fn
      "(" <> tuple ->
        %{
          "type" => "tuple",
          "name" => "",
          "components" => tuple |> String.trim_trailing(")") |> abi_types()
        }

      type ->
        %{"type" => type, "name" => ""}
    end)
  end

  defp split_types(value) do
    {parts, current, _depth} =
      value
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        "(", {parts, current, depth} -> {parts, current <> "(", depth + 1}
        ")", {parts, current, depth} -> {parts, current <> ")", depth - 1}
        ",", {parts, current, 0} -> {[current | parts], "", 0}
        char, {parts, current, depth} -> {parts, current <> char, depth}
      end)

    Enum.reverse([current | parts])
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
