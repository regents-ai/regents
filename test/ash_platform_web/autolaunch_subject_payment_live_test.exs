defmodule AshPlatformWeb.AutolaunchSubjectWalletLiveTest do
  @moduledoc """
  The subject wallet card on the subject page: what each visitor is offered, what
  a review actually says, and what the browser is allowed to make it do.
  """

  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.SubjectWalletFixture, as: Fixture
  alias AshPlatform.TestAutolaunchSubjectWalletChainClient, as: ChainClient

  @card "#autolaunch-subject-wallet"
  @wallet Fixture.wallet()
  @approval_hash "0x" <> String.duplicate("a1", 32)
  @action_hash "0x" <> String.duplicate("b2", 32)

  # Every removed control of the superseded subject-payment lane.
  @removed_ids [
    "#subject-payment-wallet",
    "#subject-payment-review",
    "#subject-payment-link-create-form",
    "#subject-payment-link-canonical-form",
    "#subject-payment-link-state-form",
    "#subject-ingress-sweep-form",
    "#subject-stake-form",
    "#subject-unstake-form",
    "#subject-claim-usdc-form"
  ]

  setup do
    Fixture.install()
    Fixture.actor()
  end

  describe "SIGNED_OUT_EXPOSES_NO_SENDABLE_ACTION" do
    test "an anonymous visitor is offered sign-in and no wallet control at all", %{
      conn: conn,
      subject: subject
    } do
      {:ok, view, _html} = live(conn, path(subject))
      render_async(view)

      assert has_element?(view, @card, "Sign in to continue")
      refute has_element?(view, "#{@card} [data-subject-wallet-send]")
      refute has_element?(view, "#{@card} form")

      # No private fact of any wallet reaches an anonymous visitor. The subject's
      # own published addresses are page content and stay exactly as they were.
      for private <- ["Staked", "Wallet", "Review"] do
        refute has_element?(view, @card, private)
      end
    end

    test "a not-found subject mounts no wallet card whatsoever", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/autolaunch/subjects/nope-42")
      render_async(view)

      assert has_element?(view, "#autolaunch-subject-detail", "Subject not found")
      refute has_element?(view, @card)
    end

    test "the superseded lane leaves no control and no copy behind", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      {:ok, view, html} = signed_in(conn, account, subject)

      for id <- @removed_ids, do: refute(has_element?(view, id))

      for copy <- [
            "Payment links, revenue, and subject staking",
            "AutolaunchSubjectPaymentWallet",
            "Retry approval verification",
            "Retry confirmation"
          ] do
        refute html =~ copy
      end
    end
  end

  describe "ONE_ACTIVE_PRIVY_WALLET_ON_SCREEN" do
    test "no selected wallet is the ordinary empty state, reading nothing", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      {:ok, view, _html} = signed_in(conn, account, subject)

      assert has_element?(view, "#{@card} [data-subject-wallet-connect]")

      # A Solana or disconnected selection reports no address at all.
      html = active_wallet(view, nil)
      refute html =~ "Staked"
      assert has_element?(view, "#{@card} [data-subject-wallet-connect]")
    end

    test "the selected wallet's own balances and stake appear", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      {:ok, view, _html} = signed_in(conn, account, subject)
      html = active_wallet(view, @wallet)

      assert html =~ "900"
      assert html =~ "Staked"
      assert html =~ "400"
      assert has_element?(view, "#{@card}-form")
    end

    test "a wallet this account does not hold sees no private state and no control", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      {:ok, view, _html} = signed_in(conn, account, subject)
      html = active_wallet(view, "0x9999999999999999999999999999999999999999")

      assert text(html) =~ "Switch back to a wallet on this account to continue."
      refute html =~ "Staked"
      refute has_element?(view, "#{@card} [data-subject-wallet-send]")
    end

    test "a subject with no revenue split says so instead of offering an action", %{
      conn: conn,
      account: account
    } do
      subject = Fixture.subject!("subject:wallet:nosplit", splitter_address: nil)
      {:ok, view, _html} = signed_in(conn, account, subject)
      html = active_wallet(view, @wallet)

      assert text(html) =~ "This subject is not sharing revenue yet."
      refute has_element?(view, "#{@card}-form")
    end
  end

  describe "THE_REVIEW_SAYS_WHAT_WILL_HAPPEN" do
    test "a stake review shows the amount, the wallet, and its two steps", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      html = review(view, :stake, %{"amount" => "10"})

      assert html =~ "Stake"
      assert html =~ "10 SUBJECT"
      assert html =~ "Base"
      assert has_element?(view, "#{@card}-review")

      assert has_element?(
               view,
               ~s(#{@card} li[data-step="approval"]),
               "Allow SUBJECT to be spent"
             )

      assert has_element?(view, ~s(#{@card} li[data-step="action"]), "Stake")
      assert has_element?(view, "#{@card} [data-subject-wallet-send]")

      # No calldata, selector, or internal state reaches the customer.
      refute html =~ "0xa694fc3a"
      refute html =~ "prepared"
      refute html =~ "calldata"
    end

    test "a payment review states the fixed protocol share and where the rest goes", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      html = review(view, :pay, %{"asset" => "usdc", "amount" => "5"})

      assert text(html) =~ "2% of this goes to the protocol"
      assert html =~ "98%"
      assert text(html) =~ "everyone staking SUBJECT on this subject right now"
    end

    test "with nobody staked a payment review says the rest goes to the treasury", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      ChainClient.install(Fixture.fixture(total_staked: 0, staked_of: 0))
      view = ready(conn, account, subject)
      html = review(view, :pay, %{"asset" => "usdc", "amount" => "5"})

      assert text(html) =~ "Nobody is staking SUBJECT on this subject right now"
      assert text(html) =~ "goes straight to its treasury"
    end

    test "a sweep review says plainly that the signer receives nothing", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      html = review(view, :sweep, %{"asset" => "usdc"})

      assert text(html) =~ "Nothing is sent to your wallet"
      assert text(html) =~ "another sweep before yours can make this fail"
      assert html =~ "7"
    end

    test "a refused action explains itself in plain language and prepares nothing", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      html = review(view, :stake, %{"amount" => "9000"})

      assert text(html) =~ "That is more than this wallet holds."
      refute has_element?(view, "#{@card}-review")
    end

    test "Max fills the amount this action can actually use", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)

      select(view, :unstake)

      html =
        view |> element(~s(#{@card} button[phx-click="fill_subject_amount"])) |> render_click()

      assert html =~ ~s(value="400")
    end
  end

  describe "THE_BROWSER_REPORTS_A_HASH_AND_STOPS" do
    test "a claimed step is handed the reviewed bytes exactly once", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :unstake, %{"amount" => "10"})

      action_id = action_id(view)
      render_hook(element(view, @card), "sign_subject_wallet_step", %{"action-id" => action_id})

      assert_push_event(view, "autolaunch-subject-wallet:send", %{
        action_id: ^action_id,
        step: "action"
      })

      # The claimed step is no longer offered a second send.
      refute has_element?(view, "#{@card} [data-subject-wallet-send]")
    end

    test "a reported hash becomes a Basescan link and its outcome comes from the server", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :unstake, %{"amount" => "10"})
      action_id = action_id(view)

      render_hook(element(view, @card), "sign_subject_wallet_step", %{"action-id" => action_id})
      ChainClient.put(%{outcomes: %{action: %{outcome: :confirmed}}})

      html =
        render_hook(element(view, @card), "subject_wallet_submitted", %{
          "action_id" => action_id,
          "step" => "action",
          "transaction_hash" => @action_hash
        })

      assert html =~ "https://basescan.org/tx/#{@action_hash}"
      assert text(html) =~ "Confirmed on Base."
      assert_push_event(view, "autolaunch-subject-wallet:hash-durable", %{step: "action"})
    end

    test "an approval settles and the action it enables becomes sendable", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :stake, %{"amount" => "10"})
      action_id = action_id(view)

      render_hook(element(view, @card), "sign_subject_wallet_step", %{"action-id" => action_id})
      ChainClient.put(%{outcomes: %{approval: %{outcome: :confirmed}}})

      html =
        render_hook(element(view, @card), "subject_wallet_submitted", %{
          "action_id" => action_id,
          "step" => "approval",
          "transaction_hash" => @approval_hash
        })

      assert html =~ "https://basescan.org/tx/#{@approval_hash}"
      assert has_element?(view, "#{@card} [data-subject-wallet-send]")
      assert has_element?(view, ~s(#{@card} li[data-step="approval"]), "Confirmed")
    end

    test "an explicit wallet rejection ends the action and says nothing was sent", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :unstake, %{"amount" => "10"})
      action_id = action_id(view)

      render_hook(element(view, @card), "sign_subject_wallet_step", %{"action-id" => action_id})

      html =
        render_hook(element(view, @card), "subject_wallet_rejected", %{
          "action_id" => action_id,
          "code" => 4001
        })

      assert text(html) =~ "Your wallet declined this. Nothing was sent."
      refute has_element?(view, "#{@card} [data-subject-wallet-send]")
    end

    test "a send that never began returns the same review to sendable", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :unstake, %{"amount" => "10"})
      action_id = action_id(view)

      render_hook(element(view, @card), "sign_subject_wallet_step", %{"action-id" => action_id})
      refute has_element?(view, "#{@card} [data-subject-wallet-send]")

      render_hook(element(view, @card), "subject_wallet_dispatch_not_started", %{
        "action_id" => action_id
      })

      assert has_element?(view, "#{@card} [data-subject-wallet-send]")
    end

    test "a reload restores the open action from the owning account's own row", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :unstake, %{"amount" => "10"})
      action_id = action_id(view)

      reopened = ready(conn, account, subject)
      html = render_hook(element(reopened, @card), "restore_subject_wallet_operation", %{})

      assert html =~ "Unstake"
      assert action_id(reopened) == action_id
    end

    test "a verified revert is terminal and never offers another send", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :unstake, %{"amount" => "10"})
      action_id = action_id(view)

      render_hook(element(view, @card), "sign_subject_wallet_step", %{"action-id" => action_id})
      ChainClient.put(%{outcomes: %{action: %{outcome: :reverted}}})

      html =
        render_hook(element(view, @card), "subject_wallet_submitted", %{
          "action_id" => action_id,
          "step" => "action",
          "transaction_hash" => @action_hash
        })

      assert text(html) =~ "This transaction reverted on Base. Nothing moved."
      refute has_element?(view, "#{@card} [data-subject-wallet-send]")
    end

    test "a browser-reported failure never claims more than it knows", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)

      html =
        render_hook(element(view, @card), "subject_wallet_failed", %{
          "reason" => "send_unconfirmed"
        })

      assert text(html) =~ "Your wallet may have sent this transaction."

      html =
        render_hook(element(view, @card), "subject_wallet_failed", %{
          "reason" => "wallet_unavailable"
        })

      assert html =~ "Nothing was sent."
    end
  end

  describe "SWITCHING_WALLETS_CANCELS_ONLY_AN_UNDISPATCHED_REVIEW" do
    test "an undispatched review is withdrawn when the wallet changes", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :unstake, %{"amount" => "10"})
      assert has_element?(view, "#{@card}-review")

      active_wallet(view, "0x9999999999999999999999999999999999999999")
      refute has_element?(view, "#{@card}-review")
    end

    test "a claimed action stays bound to the wallet it was reviewed for", %{
      conn: conn,
      account: account,
      subject: subject
    } do
      view = ready(conn, account, subject)
      review(view, :unstake, %{"amount" => "10"})
      action_id = action_id(view)

      render_hook(element(view, @card), "sign_subject_wallet_step", %{"action-id" => action_id})

      active_wallet(view, "0x9999999999999999999999999999999999999999")

      # The wallet is not held by this account, so nothing private shows, and the
      # claimed action was not withdrawn behind the customer's back.
      assert {:ok, %{operation: open}} =
               AshPlatform.Autolaunch.open_subject_wallet_operation(
                 subject.subject_id,
                 actor: %AshPlatform.Actors.Human{human_account_id: account.id},
                 context: %{
                   session_lease: %{lineage: lineage(conn, account), account_id: account.id}
                 }
               )

      assert open.state == :dispatched
      assert open.signer == @wallet
    end
  end

  # Helpers

  defp path(subject), do: "/autolaunch/subjects/#{subject.subject_id}"

  defp signed_in(conn, account, subject) do
    conn
    |> init_test_session(%{human_account_id: account.id})
    |> live(path(subject))
  end

  defp ready(conn, account, subject) do
    {:ok, view, _html} = signed_in(conn, account, subject)
    active_wallet(view, @wallet)
    view
  end

  defp active_wallet(view, address),
    do: render_hook(element(view, @card), "subject_active_wallet", %{"address" => address})

  defp select(view, kind),
    do: view |> element("#{@card}-action-#{kind}") |> render_click()

  defp review(view, kind, params) do
    select(view, kind)
    view |> form("#{@card}-form", params) |> render_submit()
  end

  # The open action's identity, taken from whichever control the card is
  # currently showing for it.
  defp action_id(view) do
    html = render(view)

    [action_id] =
      Regex.run(~r/data-subject-wallet-send="([^"]+)"/, html, capture: :all_but_first) ||
        Regex.run(~r/phx-value-action-id="([^"]+)"/, html, capture: :all_but_first)

    action_id
  end

  # HEEx wraps long copy across source lines, so customer sentences are compared
  # against the rendered text with its whitespace collapsed.
  defp text(html), do: String.replace(html, ~r/\s+/, " ")

  defp lineage(conn, account) do
    conn
    |> init_test_session(%{human_account_id: account.id})
    |> get_session("session_lineage")
  end
end
