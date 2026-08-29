defmodule AshPlatformWeb.AutolaunchLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.AccessContext.AccountControl
  alias AshPlatform.{Accounts, Autolaunch, Discussions, Formation}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Autolaunch.{LabMarketFeed, LaunchDraft}
  alias AshPlatform.TestAutolaunchTreasuryChainClient, as: TreasuryClient
  alias AshPlatformWeb.{AutolaunchLive, RouteCatalog}

  defmodule LiveMarketReader do
    def head, do: Agent.get(agent(), & &1.head)
    def snapshots(_head, _capacity, _attempted), do: Agent.get(agent(), & &1.snapshots)
    def verify_head(_expected), do: :ok

    defp agent,
      do: Application.fetch_env!(:ash_platform, :autolaunch_live_market_test_agent)
  end

  defmodule LiveMarketProjector do
    def project(_snapshots, _head), do: {:ok, []}
  end

  defmodule MarketProbe do
    use GenServer

    def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid, name: LabMarketFeed)
    def init(test_pid), do: {:ok, test_pid}

    def handle_call(:snapshot, _from, test_pid) do
      send(test_pid, :market_snapshot_requested)
      {:reply, %{generation: 0, head: nil, degraded?: false, auctions: %{}}, test_pid}
    end
  end

  test "overview navigates to the four Autolaunch destinations", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/autolaunch")
    render_async(view)

    assert has_element?(view, "#autolaunch-overview")

    for {label, path} <- [
          {"Create", "/autolaunch/create"},
          {"Auctions", "/autolaunch/auctions"},
          {"Tokens", "/autolaunch/tokens"},
          {"Portfolio", "/autolaunch/holdings"}
        ] do
      assert has_element?(view, ~s(a.autolaunch-destination-card[href="#{path}"]), label)
    end
  end

  test "the disconnected render keeps an empty market without querying the watcher", %{conn: conn} do
    start_supervised!({MarketProbe, self()})

    conn = get(conn, "/autolaunch")

    assert html_response(conn, 200) =~ "Find the next launch"
    refute_received :market_snapshot_requested
  end

  test "a connected market page receives shared block updates without navigation", %{conn: conn} do
    block = %{
      number: 505,
      hash: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }

    binding = %{run_id: "live-market-run", rpc_url: "http://127.0.0.1:49713"}
    auction_id = Ash.UUID.generate()

    market_snapshot = %{
      auction_id: auction_id,
      auction_address: "0x1111111111111111111111111111111111111111",
      block_number: block.number,
      block_hash: block.hash
    }

    {:ok, agent} =
      Agent.start_link(fn ->
        %{
          head: {:ok, %{binding: binding, block: block}},
          snapshots:
            {:ok,
             %{
               snapshots: [market_snapshot],
               attempted: MapSet.new([market_snapshot.auction_address])
             }}
        }
      end)

    Application.put_env(:ash_platform, :autolaunch_live_market_test_agent, agent)

    on_exit(fn ->
      Application.delete_env(:ash_platform, :autolaunch_live_market_test_agent)
    end)

    {:ok, _feed} =
      start_supervised(
        {LabMarketFeed, reader: LiveMarketReader, projector: LiveMarketProjector, poll?: false}
      )

    {:ok, view, html} = live(conn, "/autolaunch")
    live_view_pid = view.pid
    refute html =~ "Local market current at block"

    LabMarketFeed.refresh()

    assert_eventually(fn ->
      render(view) =~ "Local market current at block 505."
    end)

    assert view.pid == live_view_pid
    assert has_element?(view, "#autolaunch-overview")

    sideways = %{
      block
      | hash: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }

    Agent.update(agent, &Map.put(&1, :head, {:ok, %{binding: binding, block: sideways}}))
    LabMarketFeed.refresh()

    assert_eventually(fn ->
      not (render(view) =~ "Local market current at block")
    end)

    render_patch(view, "/stake")
    refute render(view) =~ "Local market current at block"
  end

  test "auction and token routes keep identifiers and honest empty states", %{conn: conn} do
    for {path, selector, heading, empty_copy} <- [
          {"/autolaunch/auctions", "#autolaunch-auctions", "Auctions", "No auctions yet"},
          {"/autolaunch/tokens", "#autolaunch-tokens", "Tokens", "No tokens yet"},
          {"/autolaunch/auctions/auction-42", "#autolaunch-auction-detail", "Auction not found",
           "No public auction exists"},
          {"/autolaunch/tokens/token-42", "#autolaunch-token-detail", "Token not found",
           "No public token exists"}
        ] do
      {:ok, view, _html} = live(conn, path)
      html = render_async(view)

      assert has_element?(view, selector)
      assert html =~ heading
      assert html =~ empty_copy
      refute html =~ "$"
    end
  end

  test "subject routes have honest empty and not-found states", %{conn: conn} do
    {:ok, subjects, _html} = live(conn, "/autolaunch/subjects")
    assert render_async(subjects) =~ "No public subjects yet."

    {:ok, subject, _html} = live(conn, "/autolaunch/subjects/subject-42")
    html = render_async(subject)

    assert has_element?(subject, "#autolaunch-subject-detail", "Subject not found")
    assert html =~ "No public subject exists at subject-42."
    refute html =~ "$"
  end

  test "canonical subject identity format edges round-trip through public URLs", %{conn: conn} do
    edge_ids = ["Z", "A._:-" <> String.duplicate("x", 123)]

    for subject_id <- edge_ids do
      subject = import_minimal_subject!(subject_id)
      assert subject.subject_id == subject_id

      {:ok, subjects, _html} = live(conn, "/autolaunch/subjects")
      subjects_html = render_async(subjects)
      assert subjects_html =~ ~s(href="/autolaunch/subjects/#{subject_id}")

      {:ok, detail, _html} = live(conn, "/autolaunch/subjects/#{subject_id}")
      detail_html = render_async(detail)
      assert has_element?(detail, "#autolaunch-subject-detail", subject_id)
      assert detail_html =~ subject_id
    end
  end

  test "subject read errors never use not-found copy" do
    html =
      render_component(&AutolaunchLive.page/1,
        route_spec: RouteCatalog.fetch!(:autolaunch_subject, %{"id" => "subject:error"}),
        params: %{"id" => "subject:error"},
        account_control: %AccountControl{
          kind: :sign_in,
          label: "Sign In",
          profile_path: nil,
          settings_path: "/settings"
        },
        featured_auctions: [],
        recent_auctions: [],
        top_tokens: [],
        graduated_tokens: [],
        records: [],
        record: nil,
        subject_tokens: [],
        subject_actions: [],
        subject_settlements: [],
        bid_positions: [],
        returnable_positions: [],
        claimed_token_positions: [],
        launch_drafts: [],
        draft_values: %{},
        draft_errors: %{},
        status: :error,
        comments: [],
        comments_status: :ready,
        comment_request_id: Ash.UUID.generate(),
        comment_draft: "",
        comment_admin: false
      )

    assert html =~ "Subject unavailable"
    assert html =~ "This subject could not be loaded right now."
    assert html =~ ~s(role="alert")
    refute html =~ "Subject not found"
  end

  test "subject loaders render stored revenue and newest-first settlement history", %{conn: conn} do
    report = TreasuryClient.seed_verified!("0x6666666666666666666666666666666666666666")

    on_exit(fn ->
      Application.delete_env(:ash_platform, :autolaunch_treasury_chain_client)
      Application.delete_env(:ash_platform, :test_autolaunch_treasury_observation)
    end)

    subject =
      Autolaunch.import_subject!(
        "subject:live:revenue",
        "agent",
        8453,
        "0x3333333333333333333333333333333333333333",
        "0x4444444444444444444444444444444444444444",
        "0x5555555555555555555555555555555555555555",
        "0x6666666666666666666666666666666666666666",
        "0x7777777777777777777777777777777777777777",
        "0x8888888888888888888888888888888888888888",
        1500,
        250,
        200,
        "12000000",
        "3400000000000000000",
        "5000000",
        actor: %System{}
      )

    auction =
      Autolaunch.import_auction!(
        "Subject detail auction",
        nil,
        false,
        :graduated,
        DateTime.utc_now(),
        %{treasury_security_report_id: report.id},
        actor: %System{}
      )

    token =
      Autolaunch.import_subject_token!(
        auction.id,
        subject.subject_id,
        "Related Subject Token",
        "RST",
        "Linked to the subject.",
        DateTime.utc_now(),
        nil,
        actor: %System{}
      )

    older_hash = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    newer_hash = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    Autolaunch.import_subject_action!(
      subject.subject_id,
      "settle_buyback",
      "0x1111111111111111111111111111111111111111",
      8453,
      older_hash,
      "2000000",
      "confirmed",
      100,
      actor: %System{}
    )

    Process.sleep(2)

    Autolaunch.import_subject_action!(
      subject.subject_id,
      "stake",
      "0x9999999999999999999999999999999999999999",
      8453,
      "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "1",
      "confirmed",
      100,
      actor: %System{}
    )

    Process.sleep(2)

    Autolaunch.import_subject_action!(
      subject.subject_id,
      "settle_buyback",
      "0x2222222222222222222222222222222222222222",
      8453,
      newer_hash,
      "3000000",
      "pending",
      101,
      actor: %System{}
    )

    {:ok, subjects, _html} = live(conn, "/autolaunch/subjects")
    subjects_html = render_async(subjects)
    assert subjects_html =~ "subject:live:revenue"
    assert subjects_html =~ ~s(href="/autolaunch/subjects/subject:live:revenue")
    assert subjects_html =~ "0x3333333333333333333333333333333333333333"
    assert subjects_html =~ "Chain 8453"

    {:ok, detail, _html} = live(conn, "/autolaunch/subjects/#{subject.subject_id}")
    html = render_async(detail)

    assert has_element?(detail, "#autolaunch-subject-detail")
    assert has_element?(detail, "#autolaunch-subject-detail", subject.subject_id)
    assert has_element?(detail, "#subject-revenue-title", "Revenue")
    assert has_element?(detail, "#subject-related-tokens", token.name)

    assert has_element?(
             detail,
             "#subject-related-tokens a[href='/autolaunch/tokens/#{token.id}']"
           )

    assert has_element?(detail, "#subject-recent-actions", "stake")
    assert has_element?(detail, "#subject-recent-actions", "settle buyback")
    assert has_element?(detail, "#subject-settlement-title", "Settlement history")
    assert has_element?(detail, "#subject-settlement-history", "settle buyback")
    refute has_element?(detail, "#subject-settlement-history", "stake")
    assert html =~ "12000000"
    assert html =~ "3400000000000000000"
    assert html =~ "5000000"
    assert html =~ "settle buyback"
    assert html =~ newer_hash
    assert html =~ older_hash
    assert :binary.match(html, newer_hash) < :binary.match(html, older_hash)
    refute html =~ subject.id
    refute html =~ "$"
  end

  test "subject detail shows honest empty related records and no derived money", %{conn: conn} do
    subject =
      Autolaunch.import_subject!(
        "subject:live:empty",
        "project",
        8453,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        actor: %System{}
      )

    {:ok, detail, _html} = live(conn, "/autolaunch/subjects/#{subject.subject_id}")
    html = render_async(detail)

    assert has_element?(detail, "#subject-related-tokens", "No related tokens yet.")
    assert has_element?(detail, "#subject-recent-actions", "No subject actions yet.")
    assert has_element?(detail, "#subject-settlement-history", "No settlements yet.")
    refute html =~ "Ready to settle"
    refute html =~ "$"
  end

  test "launch routes have honest empty and not-found states", %{conn: conn} do
    {:ok, launches, _html} = live(conn, "/autolaunch/launches")
    assert render_async(launches) =~ "No public launches yet."

    {:ok, launch, _html} = live(conn, "/autolaunch/launches/launch-42")
    html = render_async(launch)

    assert has_element?(launch, "#autolaunch-launch-detail", "Launch not found")
    assert html =~ "No public launch exists at launch-42."
    refute html =~ "$"
  end

  test "canonical launch identity format edges round-trip through public URLs", %{conn: conn} do
    edge_ids = ["Z", "A._:-" <> String.duplicate("x", 123)]

    for job_id <- edge_ids do
      launch = import_minimal_launch!(job_id)
      assert launch.job_id == job_id

      {:ok, launches, _html} = live(conn, "/autolaunch/launches")
      launches_html = render_async(launches)
      assert launches_html =~ ~s(href="/autolaunch/launches/#{job_id}")

      {:ok, detail, _html} = live(conn, "/autolaunch/launches/#{job_id}")
      detail_html = render_async(detail)
      assert has_element?(detail, "#autolaunch-launch-detail", job_id)
      assert detail_html =~ job_id
    end
  end

  test "launch read errors never use not-found copy" do
    html =
      render_component(&AutolaunchLive.page/1,
        route_spec: RouteCatalog.fetch!(:autolaunch_launch, %{"id" => "launch:error"}),
        params: %{"id" => "launch:error"},
        account_control: %AccountControl{
          kind: :sign_in,
          label: "Sign In",
          profile_path: nil,
          settings_path: "/settings"
        },
        featured_auctions: [],
        recent_auctions: [],
        top_tokens: [],
        graduated_tokens: [],
        records: [],
        record: nil,
        subject_tokens: [],
        subject_actions: [],
        subject_settlements: [],
        bid_positions: [],
        returnable_positions: [],
        claimed_token_positions: [],
        launch_drafts: [],
        draft_values: %{},
        draft_errors: %{},
        status: :error,
        comments: [],
        comments_status: :ready,
        comment_request_id: Ash.UUID.generate(),
        comment_draft: "",
        comment_admin: false
      )

    assert html =~ "Launch unavailable"
    assert html =~ "This launch could not be loaded right now."
    assert html =~ ~s(role="alert")
    refute html =~ "Launch not found"
  end

  test "launch loaders render progress, identities, linked auction, addresses, and times", %{
    conn: conn
  } do
    auction =
      Autolaunch.import_auction!(
        "Linked launch auction",
        nil,
        false,
        :active,
        DateTime.utc_now(),
        actor: %System{}
      )

    started_at = ~U[2026-07-30 12:00:00.000000Z]
    finished_at = ~U[2026-07-30 12:45:00.000000Z]

    launch =
      import_minimal_launch!("launch:live:complete",
        auction_id: auction.id,
        status: "complete",
        step: "record_addresses",
        agent_name: "Launch Detail Agent",
        started_at: started_at,
        finished_at: finished_at
      )

    {:ok, launches, _html} = live(conn, "/autolaunch/launches")
    launches_html = render_async(launches)
    assert launches_html =~ "Launch Detail Token · LDT"
    assert launches_html =~ "complete"
    assert launches_html =~ "record addresses"
    assert launches_html =~ "Launch Detail Agent"
    assert launches_html =~ ~s(href="/autolaunch/launches/#{launch.job_id}")

    {:ok, detail, _html} = live(conn, "/autolaunch/launches/#{launch.job_id}")
    html = render_async(detail)

    assert has_element?(detail, "#autolaunch-launch-detail", "Launch Detail Token · LDT")
    assert has_element?(detail, "#launch-progress-title", "Progress")
    assert has_element?(detail, "#launch-identity-title", "Agent and token")
    assert has_element?(detail, "#launch-auction-title", "Linked auction")
    assert has_element?(detail, "#launch-addresses-title", "Published addresses")
    assert has_element?(detail, "#autolaunch-launch-detail dt", "Auction rules")
    assert has_element?(detail, "#launch-times-title", "Timeline")
    assert html =~ launch.job_id
    assert html =~ "agent:launch-detail"
    assert html =~ "Launch Detail Agent"
    assert html =~ ~s(href="/autolaunch/auctions/#{auction.id}")
    assert html =~ "0x1111111111111111111111111111111111111111"
    assert html =~ "0x2222222222222222222222222222222222222222"
    assert html =~ "0x3333333333333333333333333333333333333333"
    assert html =~ "0x4444444444444444444444444444444444444444"
    assert html =~ "0x5555555555555555555555555555555555555555"
    assert html =~ "Jul 30, 2026 at 12:00 UTC"
    assert html =~ "Jul 30, 2026 at 12:45 UTC"
    refute html =~ "$"
  end

  test "Create asks anonymous visitors to sign in and offers no draft form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/autolaunch/create")
    html = render_async(view)

    assert has_element?(view, "#autolaunch-create")
    assert html =~ "Every change is saved privately"
    assert html =~ "Sign in to prepare your launch."
    refute has_element?(view, "#autolaunch-create form")
    refute has_element?(view, ~s(#autolaunch-create button[type="submit"]))
  end

  @live_draft %{
    "name" => "Open Research",
    "symbol" => "open",
    "description" => "A launch profile awaiting review.",
    "website" => "https://example.test/open",
    "image" => "https://example.test/open.png",
    "treasury" => "0xAbCdeF0000000000000000000000000000000001",
    "required_regent_raised" => "1000.5"
  }

  test "a signed-in Human needs no Regent and may inspect the first two stages in either order",
       %{
         conn: conn
       } do
    account =
      draft_account!("autolaunch-stages", "0x3333333333333333333333333333333333333333")

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    assert has_element?(view, ~s(nav[aria-label="Launch stages"]))

    assert has_element?(
             view,
             ~s(.autolaunch-create-stages button[phx-value-stage="token_details"]),
             "Token Details"
           )

    assert has_element?(
             view,
             ~s(.autolaunch-create-stages button[phx-value-stage="treasury"]),
             "Treasury Address"
           )

    assert has_element?(
             view,
             ~s(.autolaunch-create-stages button[disabled]),
             "Launch Transactions"
           )

    refute has_element?(
             view,
             ~s(.autolaunch-create-stages button[disabled][phx-click])
           )

    refute has_element?(
             view,
             ~s(.autolaunch-create-stages button[disabled][phx-value-stage])
           )

    refute has_element?(view, "#autolaunch-create", "Form your Regent")
    refute has_element?(view, "#autolaunch-create", "Open Formation")
    assert has_element?(view, "#launch-token-details")
    assert has_element?(view, "#launch-token-details", "Recommended: 400 × 400 px")

    view
    |> element(~s(.autolaunch-create-stages button[phx-value-stage="treasury"]))
    |> render_click()

    assert has_element?(view, "#launch-treasury-details")
    assert has_element?(view, "#autolaunch-create", "Create a 2-of-3 Safe on Base")

    assert has_element?(
             view,
             ~s(.autolaunch-stage-actions button[disabled]),
             "Launch Transactions"
           )

    refute has_element?(view, ~s(.autolaunch-stage-actions button[disabled][phx-click]))
    refute has_element?(view, ~s(.autolaunch-stage-actions button[disabled][phx-value-stage]))

    view
    |> element(~s(.autolaunch-create-stages button[phx-value-stage="token_details"]))
    |> render_click()

    assert has_element?(view, "#launch-token-details")
  end

  test "partial token, treasury, and EOA warning input survives remounts and stays account-private",
       %{
         conn: conn
       } do
    account =
      draft_account!("autolaunch-autosave", "0x3333333333333333333333333333333333333334")

    actor = %Human{human_account_id: account.id}
    signed_in = init_test_session(conn, %{human_account_id: account.id})
    {:ok, view, _html} = live(signed_in, "/autolaunch/create")

    view
    |> form("#launch-token-details",
      launch_draft: %{
        "name" => "Open Research",
        "symbol" => "",
        "description" => "Still writing",
        "website" => "draft link",
        "required_regent_raised" => "1."
      }
    )
    |> render_change()

    view
    |> element(~s(.autolaunch-create-stages button[phx-value-stage="treasury"]))
    |> render_click()

    view
    |> form("#launch-treasury-details",
      launch_draft: %{
        "treasury" => "0x123",
        "treasury_path" => "eoa",
        "eoa_acknowledgement" => "I am still typing"
      }
    )
    |> render_change()

    assert {:ok, [persisted]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert persisted.name == "Open Research"
    assert persisted.symbol == ""
    assert persisted.treasury == "0x123"
    assert persisted.eoa_acknowledgement == "I am still typing"

    {:ok, restored, _html} = live(signed_in, "/autolaunch/create")
    assert has_element?(restored, ~s(#launch-token-details-name[value="Open Research"]))
    assert has_element?(restored, "#launch-token-details-description", "Still writing")

    restored
    |> element(~s(.autolaunch-create-stages button[phx-value-stage="treasury"]))
    |> render_click()

    assert has_element?(restored, ~s(#launch-treasury-details-treasury[value="0x123"]))

    assert has_element?(
             restored,
             "#launch-treasury-details-eoa-acknowledgement",
             "I am still typing"
           )

    {:ok, anonymous, _html} = live(conn, "/autolaunch/create")
    refute has_element?(anonymous, "#launch-token-details")

    other =
      draft_account!("autolaunch-autosave-other", "0x3333333333333333333333333333333333333335")

    {:ok, other_view, _html} =
      conn
      |> init_test_session(%{human_account_id: other.id})
      |> live("/autolaunch/create")

    refute has_element?(other_view, ~s(#launch-token-details-name[value="Open Research"]))
  end

  test "Create reloads the exact account-owned draft instead of a newer legacy draft", %{
    conn: conn
  } do
    account =
      draft_account!("autolaunch-active-draft", "0x3333333333333333333333333333333333333338")

    actor = %Human{human_account_id: account.id}

    account_draft =
      Autolaunch.create_launch_draft!(%{"name" => "Account launch"}, actor: actor)

    regent = Formation.form_regent!("autolaunch-active-draft", "Legacy", actor: actor)

    legacy =
      Ash.Seed.seed!(LaunchDraft, %{
        name: "Newer legacy launch",
        symbol: "LEGACY",
        human_account_id: account.id,
        regent_id: regent.id
      })

    assert {:ok, [first | _]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert first.id == legacy.id

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    assert has_element?(view, ~s(#launch-token-details-name[value="Account launch"]))
    refute has_element?(view, ~s(#launch-token-details-name[value="Newer legacy launch"]))

    assert {:ok, active} = Autolaunch.get_my_account_launch_draft(actor: actor)
    assert active.id == account_draft.id
  end

  test "an overlong EOA acknowledgement is marked and explained beside the textarea", %{
    conn: conn
  } do
    account =
      draft_account!("autolaunch-eoa-error", "0x3333333333333333333333333333333333333337")

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    view
    |> element(~s(.autolaunch-create-stages button[phx-value-stage="treasury"]))
    |> render_click()

    view
    |> form("#launch-treasury-details",
      launch_draft: %{
        "treasury" => "0x3333333333333333333333333333333333333337",
        "treasury_path" => "eoa",
        "eoa_acknowledgement" => String.duplicate("x", 513)
      }
    )
    |> render_change()

    id = "launch-treasury-details-eoa-acknowledgement"

    assert has_element?(
             view,
             "##{id}[aria-invalid=true][aria-describedby~='#{id}-warning'][aria-describedby~='#{id}-error']"
           )

    assert has_element?(view, "##{id}-error[role=alert]")
  end

  test "image upload plus complete token and treasury stages unlocks wallet transactions", %{
    conn: conn
  } do
    account =
      draft_account!("autolaunch-complete", "0x3333333333333333333333333333333333333336")

    actor = %Human{human_account_id: account.id}

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    view
    |> form("#launch-token-details",
      launch_draft: Map.drop(@live_draft, ["image", "treasury"])
    )
    |> render_change()

    upload =
      file_input(view, "#launch-token-details", :launch_image, [
        %{name: "token.png", content: png(), type: "image/png"}
      ])

    render_upload(upload, "token.png")
    assert has_element?(view, "[role=status]", "Image saved to your account.")

    view
    |> element(~s(.autolaunch-create-stages button[phx-value-stage="treasury"]))
    |> render_click()

    view
    |> form("#launch-treasury-details",
      launch_draft: %{"treasury" => @live_draft["treasury"], "treasury_path" => "safe"}
    )
    |> render_change()

    assert {:ok, [draft]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert Autolaunch.LaunchDraft.launch_ready?(draft)

    refute has_element?(
             view,
             ~s(.autolaunch-create-stages button[disabled])
           )

    assert has_element?(
             view,
             ~s(.autolaunch-create-stages button[phx-click="select_launch_stage"][phx-value-stage="transactions"])
           )

    view
    |> element(~s(.autolaunch-create-stages button[phx-value-stage="transactions"]))
    |> render_click()

    assert has_element?(view, "#launch-transactions", "Launch Transactions")
    assert has_element?(view, "#launch-transactions .launch-wallet[phx-hook]")

    assert {:ok, []} = Autolaunch.list_auctions()
    assert {:ok, []} = Autolaunch.list_tokens()
    assert {:ok, []} = Autolaunch.list_launches()
  end

  test "a second distinct image is refused without changing the first saved image", %{conn: conn} do
    account =
      draft_account!("autolaunch-one-image", "0x3333333333333333333333333333333333333337")

    actor = %Human{human_account_id: account.id}

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    first =
      file_input(view, "#launch-token-details", :launch_image, [
        %{name: "first.png", content: png(), type: "image/png"}
      ])

    render_upload(first, "first.png")
    assert {:ok, saved} = Autolaunch.get_my_launch_draft_image(actor: actor)

    repeat =
      file_input(view, "#launch-token-details", :launch_image, [
        %{name: "same.png", content: png(), type: "image/png"}
      ])

    render_upload(repeat, "same.png")
    assert {:ok, same} = Autolaunch.get_my_launch_draft_image(actor: actor)
    assert same.id == saved.id

    different =
      file_input(view, "#launch-token-details", :launch_image, [
        %{name: "different.jpg", content: jpeg(), type: "image/jpeg"}
      ])

    render_upload(different, "different.jpg")

    assert has_element?(
             view,
             "[role=alert]",
             "This account already has its one launch image."
           )

    assert {:ok, still_saved} = Autolaunch.get_my_launch_draft_image(actor: actor)
    assert still_saved.id == saved.id
  end

  test "overview, collections, and details render imported public records without invented money",
       %{
         conn: conn
       } do
    auction =
      Autolaunch.import_auction!(
        "BixBench launch",
        "A public research launch.",
        true,
        :active,
        DateTime.utc_now(),
        actor: %System{}
      )

    token =
      Autolaunch.import_token!(
        auction.id,
        "Bix Token",
        "BIX",
        "Graduated from BixBench launch.",
        DateTime.utc_now(),
        1,
        actor: %System{}
      )

    {:ok, overview, _html} = live(conn, "/autolaunch")
    overview_html = render_async(overview)
    assert overview_html =~ "BixBench launch"
    assert overview_html =~ "Bix Token"
    refute overview_html =~ "$"

    {:ok, auctions, _html} = live(conn, "/autolaunch/auctions")
    assert render_async(auctions) =~ "BixBench launch"

    {:ok, tokens, _html} = live(conn, "/autolaunch/tokens")
    assert render_async(tokens) =~ "BIX"

    {:ok, auction_view, _html} = live(conn, "/autolaunch/auctions/#{auction.id}")
    assert render_async(auction_view) =~ "A public research launch."

    {:ok, token_view, _html} = live(conn, "/autolaunch/tokens/#{token.id}")
    assert render_async(token_view) =~ "Graduated from BixBench launch."
  end

  test "auction and token details share the newest-first comment ledger without reactions", %{
    conn: conn
  } do
    auction =
      Autolaunch.import_auction!(
        "Commented launch",
        nil,
        false,
        :active,
        DateTime.utc_now(),
        actor: %System{}
      )

    token =
      Autolaunch.import_token!(
        auction.id,
        "Commented token",
        "COM",
        nil,
        DateTime.utc_now(),
        nil,
        actor: %System{}
      )

    account =
      Accounts.register_verified!(
        "did:privy:autolaunch-comment-#{Elixir.System.unique_integer([:positive])}",
        "0x2222222222222222222222222222222222222222",
        ["0x2222222222222222222222222222222222222222"],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}

    Discussions.post_comment!(
      :autolaunch_auction,
      auction.id,
      "Newest auction note",
      Ash.UUID.generate(),
      actor: actor
    )

    Discussions.post_comment!(
      :autolaunch_token,
      token.id,
      "Newest token note",
      Ash.UUID.generate(),
      actor: actor
    )

    for {path, copy} <- [
          {"/autolaunch/auctions/#{auction.id}", "Newest auction note"},
          {"/autolaunch/tokens/#{token.id}", "Newest token note"}
        ] do
      {:ok, view, _html} = live(conn, path)
      html = render_async(view)
      assert has_element?(view, "#comment-ledger article", copy)
      refute html =~ "reaction"
      refute html =~ "vote"
    end
  end

  defp import_minimal_subject!(subject_id) do
    Autolaunch.import_subject!(
      subject_id,
      "agent",
      8453,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      actor: %System{}
    )
  end

  defp draft_account!(did, wallet) do
    Accounts.register_verified!("did:privy:#{did}", wallet, [wallet], actor: %System{})
  end

  defp png,
    do:
      File.read!(
        "priv/static/notebooks/2152a57337000ef5b8e2233d4cad237d4edbd92131cdec553437aef422719f3b/favicon-16x16.png"
      )

  defp jpeg, do: File.read!("priv/static/images/redeem/animata1and2-poster.jpg")

  defp import_minimal_launch!(job_id, attrs \\ []) do
    Autolaunch.import_launch!(
      job_id,
      Keyword.get(attrs, :status, "running"),
      Keyword.get(attrs, :step, "deploy_token"),
      Keyword.get(attrs, :agent_id, "agent:launch-detail"),
      Keyword.get(attrs, :agent_name),
      Keyword.get(attrs, :token_name, "Launch Detail Token"),
      Keyword.get(attrs, :token_symbol, "LDT"),
      8453,
      Keyword.get(attrs, :auction_id),
      "0x1111111111111111111111111111111111111111",
      "0x2222222222222222222222222222222222222222",
      "0x3333333333333333333333333333333333333333",
      "0x4444444444444444444444444444444444444444",
      "0x5555555555555555555555555555555555555555",
      Keyword.get(attrs, :started_at),
      Keyword.get(attrs, :finished_at),
      actor: %System{}
    )
  end

  defp assert_eventually(callback, attempts \\ 50)

  defp assert_eventually(callback, attempts) when attempts > 0 do
    if callback.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(callback, attempts - 1)
    end
  end

  defp assert_eventually(_callback, 0), do: flunk("condition did not become true")
end
