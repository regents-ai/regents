defmodule AshPlatformWeb.AutolaunchLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch, Discussions, Formation}
  alias AshPlatform.Actors.{Human, System}

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

  test "Create explains optional reputation and asks anonymous visitors to sign in", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/autolaunch/create")
    html = render_async(view)

    assert has_element?(view, "#autolaunch-create")
    assert html =~ "review every bid and money action in your wallet"

    for signal <- ["Verified X", "Verified Farcaster", "Verified ENS", "Verified World"] do
      assert html =~ signal
    end

    assert html =~ "None is required to sign in or create."
    assert html =~ "Sign in to prepare your launch."
    refute has_element?(view, "#autolaunch-create form")
    refute has_element?(view, ~s(#autolaunch-create button[type="submit"]))
  end

  test "a signed-in human with a formed Regent creates and reviews a private launch draft", %{
    conn: conn
  } do
    account =
      Accounts.register_verified!(
        "did:privy:autolaunch-draft-live",
        "0x3333333333333333333333333333333333333333",
        ["0x3333333333333333333333333333333333333333"],
        actor: %System{}
      )

    Formation.form_regent!("launch-regent", "Launch Regent",
      actor: %Human{human_account_id: account.id}
    )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/create")

    assert has_element?(view, "#create-launch-draft")

    view
    |> form("#create-launch-draft",
      launch_draft: %{
        title: "Open Research Launch",
        token_name: "Open Research",
        symbol: "OPEN",
        summary: "A public profile awaiting auction design."
      }
    )
    |> render_submit()

    assert has_element?(view, "#launch-drafts article", "Open Research Launch")
    assert render(view) =~ "Draft saved. No auction or wallet action has started."

    actor = %Human{human_account_id: account.id}
    assert {:ok, [draft]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert draft.symbol == "OPEN"
    assert {:ok, []} = Autolaunch.list_auctions()
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
end
