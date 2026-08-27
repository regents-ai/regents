defmodule AshPlatformWeb.AutolaunchLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.AccessContext.AccountControl
  alias AshPlatform.{Accounts, Autolaunch, Discussions, Formation}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.TestAutolaunchTreasuryChainClient, as: TreasuryClient
  alias AshPlatformWeb.{AutolaunchLive, RouteCatalog}

  test "overview has the four founder market sections without fabricated records", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/autolaunch")
    html = render_async(view)

    assert has_element?(view, "#autolaunch-overview")

    for heading <- [
          "Featured auctions",
          "Recently created",
          "Top tokens",
          "Recently graduated"
        ] do
      assert has_element?(view, "#autolaunch-overview h2", heading)
    end

    assert has_element?(view, ~s(a[href="/autolaunch/auctions"]), "Browse auctions")
    assert has_element?(view, ~s(a[href="/autolaunch/tokens"]), "Browse tokens")
    assert has_element?(view, ~s(a[href="/autolaunch/create"]), "Create a launch")
    assert html =~ "No public records yet."
    refute html =~ "$"
  end

  test "auction and token routes keep identifiers and honest empty states", %{conn: conn} do
    for {path, selector, heading, empty_copy} <- [
          {"/autolaunch/auctions", "#autolaunch-auctions", "Auctions", "No public records yet."},
          {"/autolaunch/tokens", "#autolaunch-tokens", "Tokens", "No public records yet."},
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
    assert html =~ "Drafts stay private to you"
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

  test "Create writes the seven clean-V1 fields and reviews them without starting anything", %{
    conn: conn
  } do
    account =
      draft_account!("autolaunch-draft-live", "0x3333333333333333333333333333333333333333")

    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("launch-regent", "Launch Regent", actor: actor)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    view |> form("#create-launch-draft", launch_draft: @live_draft) |> render_submit()

    assert {:ok, [draft]} = Autolaunch.list_my_launch_drafts(actor: actor)
    card = "#launch-draft-#{draft.id}"

    assert has_element?(view, "#{card} h3", "Open Research")

    for value <- Map.values(Map.delete(@live_draft, "name")) do
      assert has_element?(view, "#{card} .autolaunch-draft-review dd", value)
    end

    assert has_element?(view, "[role=status]", "Draft saved.")

    # The saved draft is what tells the browser the form was cleared rather than
    # refused, so the next draft may start from the wallet again.
    assert has_element?(view, ~s(#create-launch-draft[data-saved-drafts="1"]))
    refute has_element?(view, "#create-launch-draft[data-draft-errors]")

    # Preparing a draft never produces a public record of any kind.
    assert {:ok, []} = Autolaunch.list_auctions()
    assert {:ok, []} = Autolaunch.list_tokens()
    assert {:ok, []} = Autolaunch.list_launches()

    {:ok, launches, _html} = live(conn, "/autolaunch/launches")
    refute render_async(launches) =~ draft.name
  end

  test "a rejected create keeps every submitted value and names the field that failed", %{
    conn: conn
  } do
    account =
      draft_account!("autolaunch-draft-invalid", "0x3333333333333333333333333333333333333334")

    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("invalid-regent", "Invalid Regent", actor: actor)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    submitted = %{@live_draft | "treasury" => "0xnope", "required_regent_raised" => "0"}
    view |> form("#create-launch-draft", launch_draft: submitted) |> render_submit()

    assert {:ok, []} = Autolaunch.list_my_launch_drafts(actor: actor)

    for {field, value} <- Map.delete(submitted, "description") do
      assert has_element?(view, ~s(#create-launch-draft-#{field}[value="#{value}"]))
    end

    assert has_element?(view, "#create-launch-draft-description", submitted["description"])

    assert has_element?(
             view,
             ~s(#create-launch-draft-treasury[aria-invalid="true"][aria-describedby~="create-launch-draft-treasury-error"])
           )

    assert has_element?(
             view,
             "#create-launch-draft-treasury-error",
             "must start with 0x and hold exactly 40 hexadecimal characters"
           )

    assert has_element?(
             view,
             "#create-launch-draft-required_regent_raised-error",
             "must be greater than zero"
           )

    assert has_element?(view, "[role=alert]", "That draft could not be saved.")

    # Every address on a refused form is the customer's, and this is how the
    # browser knows not to write over one of them.
    assert has_element?(
             view,
             ~s(#create-launch-draft[data-draft-errors="true"][data-saved-drafts="0"])
           )
  end

  test "new and saved drafts keep signer and immutable treasury separate", %{conn: conn} do
    account =
      draft_account!("autolaunch-draft-hint", "0x3333333333333333333333333333333333333337")

    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("hint-regent", "Hint Regent", actor: actor)
    draft = Autolaunch.create_launch_draft!(@live_draft, actor: actor)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    address_hint = "0x followed by exactly 40 hexadecimal characters."
    revise_hint = "#revise-launch-draft-#{draft.id}-treasury-hint"

    assert has_element?(view, "#create-launch-draft-treasury-hint", address_hint)

    refute has_element?(
             view,
             ~s(#create-launch-draft-treasury[value="0x3333333333333333333333333333333333333337"])
           )

    assert has_element?(view, "#autolaunch-create", "Create a 2-of-3 Safe on Base")
    assert has_element?(view, "#autolaunch-create", "Use existing Safe")

    # A revision starts from the treasury already saved on the draft, so its help
    # claims nothing about the wallet on screen.
    assert has_element?(view, revise_hint, address_hint)
  end

  test "a rejected revision keeps the submitted values on that card and stores nothing", %{
    conn: conn
  } do
    account =
      draft_account!("autolaunch-draft-revision", "0x3333333333333333333333333333333333333335")

    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("revision-regent", "Revision Regent", actor: actor)
    draft = Autolaunch.create_launch_draft!(@live_draft, actor: actor)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    form_id = "revise-launch-draft-#{draft.id}"
    submitted = %{@live_draft | "name" => "Renamed Research", "symbol" => ""}
    view |> form("##{form_id}", launch_draft: submitted) |> render_submit()

    assert has_element?(view, ~s(##{form_id}-name[value="Renamed Research"]))
    assert has_element?(view, ~s(##{form_id}-symbol[aria-invalid="true"]))
    assert has_element?(view, "##{form_id}-symbol-error", "is required")
    assert has_element?(view, "[role=alert]", "That draft could not be updated.")

    assert {:ok, [persisted]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert {persisted.name, persisted.symbol} == {"Open Research", "open"}

    view
    |> form("##{form_id}", launch_draft: %{@live_draft | "name" => "Renamed Research"})
    |> render_submit()

    assert has_element?(view, "#launch-draft-#{draft.id} h3", "Renamed Research")
    refute has_element?(view, "##{form_id}-symbol-error")
    assert has_element?(view, "[role=status]", "Draft updated.")
  end

  test "Create drops the superseded launch vocabulary and offers no forward action", %{conn: conn} do
    account =
      draft_account!("autolaunch-draft-inert", "0x3333333333333333333333333333333333333336")

    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("inert-regent", "Inert Regent", actor: actor)
    Autolaunch.create_launch_draft!(@live_draft, actor: actor)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    for retired <- [
          "Launch title",
          "Token name",
          "Public summary",
          "ERC-8004",
          "quarantine",
          "launch fee",
          "Launch now"
        ] do
      refute has_element?(view, "#autolaunch-create", retired)
    end

    # The draft form only ever saves a draft and never asks a wallet to send.
    # The one authorized wallet surface here is the reviewed launch card.
    assert has_element?(view, ~s(#create-launch-draft[phx-hook="AutolaunchLaunchDraft"]))
    refute has_element?(view, ".autolaunch-draft-form [phx-hook]")
    refute has_element?(view, ".autolaunch-draft-form [phx-click]")
    refute has_element?(view, ".autolaunch-draft-form [data-launch-wallet-send]")
    assert has_element?(view, ".autolaunch-draft-workspace a", "official Safe creation flow")
    assert has_element?(view, ".autolaunch-draft-workspace .launch-wallet[phx-hook]")
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
end
