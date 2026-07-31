defmodule AshPlatform.Autolaunch.BuybackActionsTest do
  use AshPlatformWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.WalletActions.Envelope

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @router "0x3333333333333333333333333333333333333333"
  @treasury "0x4444444444444444444444444444444444444444"
  @subject_id "0x" <> String.duplicate("42", 32)
  @hash "0x" <> String.duplicate("ab", 32)
  @now ~U[2026-07-31 12:00:00Z]

  defmodule ReferenceHttpStub do
    def get(url, _opts) do
      send(self(), {:reference_get, url})

      case Process.get(:reference_result, {:ok, "1"}) do
        {:ok, price} ->
          {:ok,
           %{
             status: 200,
             body: %{"data" => %{"attributes" => %{"price_usd" => price}}}
           }}

        :unavailable ->
          {:ok, %{status: 503, body: %{}}}

        {:http_status, status} ->
          {:ok, %{status: status, body: %{}}}

        :malformed ->
          {:ok, %{status: 200, body: %{}}}

        {:error, reason} ->
          {:error, reason}

        {:raise, exception} ->
          raise exception
      end
    end
  end

  defmodule ChainStub do
    @behaviour AshPlatform.Autolaunch.BuybackChainClient

    @impl true
    def confirm(envelope, hash) do
      send(Process.get(:buyback_test_pid), {:confirm, envelope, hash})

      case Process.get(:confirmation_result, :ok) do
        :ok -> {:ok, %{transaction_hash: hash, receipt_verified: true}}
        :reverted -> {:error, :transaction_reverted}
        :pending -> {:error, :transaction_pending}
      end
    end
  end

  setup do
    previous = %{
      reference_client:
        Application.get_env(:ash_platform, :autolaunch_buyback_reference_http_client),
      reference_url: Application.get_env(:ash_platform, :autolaunch_buyback_reference_url),
      chain_client: Application.get_env(:ash_platform, :autolaunch_buyback_chain_client),
      clock: Application.get_env(:ash_platform, :wallet_action_clock)
    }

    Application.put_env(
      :ash_platform,
      :autolaunch_buyback_reference_http_client,
      ReferenceHttpStub
    )

    Application.put_env(
      :ash_platform,
      :autolaunch_buyback_reference_url,
      "https://oracle.invalid/buyback-test"
    )

    Application.put_env(:ash_platform, :autolaunch_buyback_chain_client, ChainStub)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> @now end)
    Process.put(:buyback_test_pid, self())

    on_exit(fn ->
      restore(:autolaunch_buyback_reference_http_client, previous.reference_client)
      restore(:autolaunch_buyback_reference_url, previous.reference_url)
      restore(:autolaunch_buyback_chain_client, previous.chain_client)
      restore(:wallet_action_clock, previous.clock)
      Process.delete(:reference_result)
      Process.delete(:confirmation_result)
      Process.delete(:buyback_test_pid)
    end)

    {:ok, account} =
      Accounts.register_verified(
        "did:privy:s2-buyback",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    subject = subject!()
    token = token!(subject)

    %{
      actor: %Human{human_account_id: account.id},
      subject: subject,
      token: token
    }
  end

  test "prepares the stored five-argument router call at every inclusive guard boundary", %{
    actor: actor,
    subject: subject,
    token: token
  } do
    for source <- ~w(twap pool_twap uniswap_twap),
        price <- ["0.9", "1.1"] do
      set_price!(token, price, source, DateTime.add(@now, -900, :second))

      assert {:ok, envelope} =
               Autolaunch.prepare_buyback_settlement(
                 subject.subject_id,
                 @wallet,
                 "11",
                 "10",
                 actor: actor
               )

      assert envelope.resource == "autolaunch_buyback"
      assert envelope.action == "settle_treasury_buyback"
      assert envelope.chain_id == 8453
      assert envelope.to == @router
      assert envelope.expected_signer == @wallet
      assert envelope.value == "0"
      assert envelope.approval == nil
      assert envelope.arguments.treasury == @treasury
      assert envelope.arguments.amount_usdc_atomic == "11000000"
      assert envelope.arguments.minimum_regent_output_atomic == "10000000000000000000"
      assert String.starts_with?(envelope.data, "0xd8df40b6")
      assert Envelope.valid?(envelope)
      assert_receive {:reference_get, "https://oracle.invalid/buyback-test"}
    end
  end

  test "rejects one unit beyond pending without contacting the reference client", %{
    actor: actor,
    subject: subject
  } do
    log =
      capture_log(fn ->
        assert {:error, :buyback_market_paused} =
                 Autolaunch.prepare_buyback_settlement(
                   subject.subject_id,
                   @wallet,
                   "11.000001",
                   "10",
                   actor: actor
                 )
      end)

    assert log =~ "amount_exceeds_pending_balance"
    refute_received {:reference_get, _url}
  end

  test "rejects one second beyond the 900-second TWAP age", %{
    actor: actor,
    subject: subject,
    token: token
  } do
    set_price!(token, "1", "twap", DateTime.add(@now, -901, :second))

    assert_paused(actor, subject, "11", "10", "twap_age_out_of_range")
  end

  test "rejects one microsecond beyond the 900-second TWAP age", %{
    actor: actor,
    subject: subject,
    token: token
  } do
    set_price!(token, "1", "twap", DateTime.add(@now, -900_000_001, :microsecond))

    assert_paused(actor, subject, "11", "10", "twap_age_out_of_range")
  end

  test "rejects either side one step beyond the 1000bps TWAP band", %{
    actor: actor,
    subject: subject,
    token: token
  } do
    for price <- ["0.899999999999999999", "1.100000000000000001"] do
      set_price!(token, price, "twap", @now)
      assert_paused(actor, subject, "11", "10", "twap_outside_reference_band")
    end
  end

  test "rejects minimum output one wei below the reference plus 1000bps boundary", %{
    actor: actor,
    subject: subject
  } do
    assert_paused(
      actor,
      subject,
      "11",
      "9.999999999999999999",
      "minimum_output_below_reference_floor"
    )
  end

  test "rejects unapproved TWAP sources and unavailable references with one public reason", %{
    actor: actor,
    subject: subject,
    token: token
  } do
    set_price!(token, "1", "spot", @now)
    assert_paused(actor, subject, "11", "10", "twap_source_not_allowed")
    refute_received {:reference_get, _url}

    set_price!(token, "1", "pool_twap", @now)
    Process.put(:reference_result, :unavailable)
    assert_paused(actor, subject, "11", "10", "reference_price_unavailable")
  end

  test "logs distinct reference failure categories while returning one customer error", %{
    actor: actor,
    subject: subject
  } do
    for {result, category} <- [
          {{:http_status, 503}, "category=http_status status=503"},
          {:malformed, "category=malformed_body"},
          {{:error, :timeout}, "category=timeout"},
          {{:raise, RuntimeError.exception("reference exploded")},
           "category=exception exception=RuntimeError"}
        ] do
      Process.put(:reference_result, result)

      log =
        capture_log(fn ->
          assert {:error, :buyback_market_paused} =
                   Autolaunch.prepare_buyback_settlement(
                     subject.subject_id,
                     @wallet,
                     "11",
                     "10",
                     actor: actor
                   )
        end)

      assert log =~ category
    end
  end

  test "rejects a system-imported non-Base subject before preparing an envelope", %{
    actor: actor
  } do
    subject =
      subject!(
        subject_id: "0x" <> String.duplicate("43", 32),
        chain_id: 1
      )

    assert {:error, :unsupported_chain} =
             Autolaunch.prepare_buyback_settlement(
               subject.subject_id,
               @wallet,
               "11",
               "10",
               actor: actor
             )

    refute_received {:reference_get, _url}
  end

  test "wrong signer, amount precision and stored contract identity fail closed", %{
    actor: actor,
    subject: subject
  } do
    assert {:error, :wrong_signer} =
             Autolaunch.prepare_buyback_settlement(
               subject.subject_id,
               @other,
               "11",
               "10",
               actor: actor
             )

    assert {:error, :invalid_amount_precision} =
             Autolaunch.prepare_buyback_settlement(
               subject.subject_id,
               @wallet,
               "0.0000001",
               "10",
               actor: actor
             )

    assert {:error, :invalid_subject_identity} =
             Autolaunch.prepare_buyback_settlement(
               subject!(subject_id: "subject:not-bytes32").subject_id,
               @wallet,
               "11",
               "10",
               actor: actor
             )
  end

  test "confirmation and restoration accept an expired submitted envelope but reject drift", %{
    actor: actor,
    subject: subject
  } do
    {:ok, envelope} = prepare(subject, actor)

    other_account =
      Accounts.register_verified!(
        "did:privy:s2-buyback-wrong-confirmer",
        @other,
        [@other],
        actor: %System{}
      )

    assert {:error, :wrong_signer} =
             Autolaunch.confirm_buyback_wallet_action(envelope, @hash,
               actor: %Human{human_account_id: other_account.id}
             )

    refute_received {:confirm, _, _}

    Application.put_env(:ash_platform, :wallet_action_clock, fn ->
      DateTime.add(@now, 601, :second)
    end)

    refute Envelope.valid?(envelope)
    assert Envelope.valid_for_confirmation?(envelope)

    assert {:ok, %{transaction_hash: @hash, subject: refreshed}} =
             Autolaunch.confirm_buyback_wallet_action(envelope, @hash, actor: actor)

    assert refreshed.subject_id == subject.subject_id
    assert_receive {:confirm, ^envelope, @hash}

    string_envelope = Jason.decode!(Jason.encode!(envelope))

    assert {:ok, restored} =
             Autolaunch.restore_submitted_buyback_action(string_envelope, actor: actor)

    assert restored.action_id == envelope.action_id

    for changed <- [
          %{envelope | to: @other},
          %{envelope | data: "0xdeadbeef"},
          put_in(envelope.arguments.treasury, @other),
          put_in(envelope.arguments.subject_id, "0x" <> String.duplicate("43", 32))
        ] do
      assert {:error, _reason} =
               Autolaunch.confirm_buyback_wallet_action(changed, @hash, actor: actor)

      refute_received {:confirm, _, _}
    end
  end

  test "confirmation distinguishes reverted and pending receipts without recording value movement",
       %{
         actor: actor,
         subject: subject
       } do
    {:ok, envelope} = prepare(subject, actor)

    Process.put(:confirmation_result, :reverted)

    assert {:ok, %{receipt_verified: true, transaction_reverted: true}} =
             Autolaunch.confirm_buyback_wallet_action(envelope, @hash, actor: actor)

    Process.put(:confirmation_result, :pending)

    assert {:error, :transaction_pending} =
             Autolaunch.confirm_buyback_wallet_action(envelope, @hash, actor: actor)
  end

  test "tests use only injectable clients and reserved invalid endpoints" do
    source = File.read!("test/ash_platform/autolaunch/buyback_actions_test.exs")
    assert source =~ ":autolaunch_buyback_reference_http_client"
    assert source =~ ":autolaunch_buyback_chain_client"
    assert source =~ "oracle.invalid"
    refute source =~ "api.gecko" <> "terminal.com"
  end

  defp assert_paused(actor, subject, amount, minimum_output, internal_reason) do
    log =
      capture_log(fn ->
        assert {:error, :buyback_market_paused} =
                 Autolaunch.prepare_buyback_settlement(
                   subject.subject_id,
                   @wallet,
                   amount,
                   minimum_output,
                   actor: actor
                 )
      end)

    assert log =~ internal_reason
    refute log =~ "Req.TransportError"
  end

  defp prepare(subject, actor) do
    Autolaunch.prepare_buyback_settlement(
      subject.subject_id,
      @wallet,
      "11",
      "10",
      actor: actor
    )
  end

  defp subject!(overrides \\ []) do
    subject_id = Keyword.get(overrides, :subject_id, @subject_id)
    chain_id = Keyword.get(overrides, :chain_id, 8453)

    subject =
      Autolaunch.import_subject!(
        subject_id,
        "agent",
        chain_id,
        "0x5555555555555555555555555555555555555555",
        nil,
        nil,
        @treasury,
        nil,
        @wallet,
        1500,
        250,
        200,
        "0",
        "0",
        "11000000",
        actor: %System{}
      )

    Autolaunch.set_subject_buyback_router!(subject, @router, actor: %System{})
  end

  defp token!(subject) do
    auction =
      Autolaunch.import_auction!(
        "S2 buyback guard",
        nil,
        false,
        :graduated,
        DateTime.add(@now, -3_600, :second),
        actor: %System{}
      )

    token =
      Autolaunch.import_subject_token!(
        auction.id,
        subject.subject_id,
        "Buyback Subject",
        "BUY",
        nil,
        DateTime.add(@now, -3_600, :second),
        nil,
        actor: %System{}
      )

    set_price!(token, "1", "twap", @now)
  end

  defp set_price!(token, price, source, updated_at) do
    Autolaunch.set_subject_token_price!(
      token,
      price,
      source,
      updated_at,
      actor: %System{}
    )
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
