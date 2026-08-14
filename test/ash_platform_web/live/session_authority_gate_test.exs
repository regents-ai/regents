defmodule AshPlatformWeb.Live.SessionAuthorityGateTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch
  alias AshPlatformWeb.Live.Session

  @wallet "0x1111111111111111111111111111111111111111"
  @auction_address "0x3333333333333333333333333333333333333333"
  @quote_token "0x4444444444444444444444444444444444444444"
  @profile "#account-control [data-account-target=profile]"
  @sign_in "#account-control [data-account-target=sign-in]"
  @signed_in_markup ~s(data-account-target="sign-out")

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: the static token names only a lineage the render proved" do
    # Phoenix LiveView 1.2.7 hands mount/3 `Map.merge(handshake_session,
    # static_token_session)`. The static token therefore carries no authority
    # field, and names a lineage only while that render's own claim was current.
    assert Session.render_lineage(%{assigns: %{current_lineage: "a-lineage"}}) ==
             %{"render_lineage" => "a-lineage"}

    assert Session.render_lineage(%{assigns: %{current_lineage: nil}}) == %{}
  end

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: an already-sent static render loses to the current handshake",
       %{conn: conn} do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})

    # The dead render happens under the exact claim of its own moment.
    static = get(signed_in, "/formation")
    assert html_response(static, 200) =~ @signed_in_markup

    # Two refreshes land before that already-sent page connects its socket.
    assert {:ok, :refresh, current} = SessionAuthority.sign_in(claim(signed_in), account.id)
    assert {:ok, :refresh, later} = SessionAuthority.sign_in(current, account.id)

    {:ok, view, _html} = static |> connects_with(SessionAuthority.session(later)) |> live()

    assert has_element?(view, @profile)
  end

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: an invalid handshake reloads once and never mounts anonymous",
       %{conn: conn} do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})
    current = get_session(signed_in)

    for handshake <- [
          %{current | "session_generation" => current["session_generation"] - 1},
          %{current | "session_generation" => current["session_generation"] + 1},
          %{current | "live_socket_id" => SessionAuthority.topic(other_lineage())},
          Map.delete(current, "live_socket_id"),
          %{}
        ] do
      assert {:error, {:redirect, %{to: "/formation"}}} =
               signed_in |> connects_with(handshake) |> live("/formation")
    end

    # A page rendered while the claim was still current, then revoked under it.
    static = get(signed_in, "/formation")
    assert SessionAuthority.revoke(claim(signed_in))

    assert {:error, {:redirect, %{to: "/formation"}}} =
             static |> connects_with(current) |> live()
  end

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: the reload settles without looping", %{conn: conn} do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})
    current = get_session(signed_in)
    assert SessionAuthority.revoke(claim(signed_in))

    # The reloaded page renders under the same revoked cookie, so it names no
    # lineage and the next connect mounts anonymous instead of reloading again.
    reloaded = get(signed_in, "/formation")
    refute html_response(reloaded, 200) =~ @signed_in_markup

    {:ok, view, _html} = reloaded |> connects_with(current) |> live()
    assert has_element?(view, @sign_in, "Sign In")
  end

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: a cookie-less first visit mounts anonymous" do
    {:ok, view, _html} = live(build_conn(), "/formation")

    assert has_element?(view, @sign_in, "Sign In")
  end

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: a different current lineage reloads the same route once",
       %{conn: conn} do
    page = init_test_session(conn, %{human_account_id: account!().id})
    browser = init_test_session(build_conn(), %{human_account_id: account!().id})

    assert {:error, {:redirect, %{to: "/formation"}}} =
             page |> connects_with(get_session(browser)) |> live("/formation")

    # The reloaded page is signed for the browser's own lineage and mounts.
    {:ok, view, _html} = live(browser, "/formation")
    assert has_element?(view, @profile)
  end

  test "MOUNTED_LEASE_POLICY_C: a mounted socket survives drift and dies on revocation", %{
    conn: conn
  } do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})

    {:ok, view, _html} = live(signed_in, "/formation")
    assert has_element?(view, @profile)

    assert {:ok, :refresh, _drifted} = SessionAuthority.sign_in(claim(signed_in), account.id)
    render_click(view, "refresh_verified_connections", %{})
    assert has_element?(view, @profile)

    # A live navigation over the same transport revalidates under the drift.
    assert render_patch(view, "/settings") =~ @signed_in_markup

    assert SessionAuthority.revoke(claim(signed_in))
    render_click(view, "refresh_verified_connections", %{})
    assert has_element?(view, @sign_in, "Sign In")
  end

  test "MOUNTED_LEASE_POLICY_C: a mounted socket dies when the account's provider evidence lapses",
       %{conn: conn} do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})

    {:ok, view, _html} = live(signed_in, "/formation")
    assert has_element?(view, @profile)

    assert {:ok, _lapsed} = Accounts.refresh_verified(account, nil, [], actor: %System{})

    render_click(view, "refresh_verified_connections", %{})
    assert has_element?(view, @sign_in, "Sign In")

    # The lapsed lease can no longer navigate into private routes either.
    assert {:error, {:redirect, %{to: "/"}}} = render_patch(view, "/settings")
  end

  test "MOUNTED_LEASE_POLICY_C: an invalid claim exposes no private dead render", %{conn: conn} do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})
    current = get_session(signed_in)

    assert html_response(get(signed_in, "/formation"), 200) =~ @signed_in_markup

    for session <- [
          %{current | "session_generation" => current["session_generation"] - 1},
          %{current | "session_generation" => current["session_generation"] + 1},
          %{current | "live_socket_id" => SessionAuthority.topic(other_lineage())},
          Map.delete(current, "live_socket_id"),
          %{}
        ] do
      dead =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(session)
        |> get("/formation")
        |> html_response(200)

      refute dead =~ @signed_in_markup
      assert dead =~ ~s(data-account-target="sign-in")
    end
  end

  test "STALE_LOGOUT_REVOKES: logout disconnects the socket and a reconnect cannot restore it", %{
    conn: conn
  } do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})
    topic = get_session(signed_in, :live_socket_id)
    AshPlatformWeb.Endpoint.subscribe(topic)

    {:ok, view, _html} = live(signed_in, "/formation")
    assert Process.alive?(view.pid)

    deleted =
      build_conn()
      |> init_test_session(get_session(signed_in))
      |> put_valid_csrf()
      |> delete("/auth/privy/session")

    assert %{"ok" => true} = json_response(deleted, 200)
    assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "disconnect"}

    {:ok, reconnected, _html} = live(signed_in, "/formation")
    assert has_element?(reconnected, @sign_in, "Sign In")
  end

  test "CENTRAL_CURRENT_ACTOR: revocation denies later wallet-action preparation at the boundary",
       %{conn: conn} do
    account =
      Accounts.register_verified!("did:privy:session-gate-prepare", @wallet, [@wallet],
        actor: %System{}
      )

    path = "/api/autolaunch/v1/auctions/#{auction!().id}/bids"
    params = %{"amount" => "12.5", "max_price" => "3"}
    signed_in = init_test_session(conn, %{human_account_id: account.id})

    assert %{"data" => prepared} = signed_in |> post(path, params) |> json_response(200)
    assert prepared["expected_signer"] == @wallet

    assert SessionAuthority.revoke(claim(signed_in))

    assert %{"error" => "unauthorized"} =
             build_conn()
             |> Phoenix.ConnTest.init_test_session(get_session(signed_in))
             |> post(path, params)
             |> json_response(401)
  end

  defp account! do
    Accounts.register_verified!(
      "did:privy:session-gate:#{Elixir.System.unique_integer([:positive])}",
      @wallet,
      [@wallet],
      actor: %System{}
    )
  end

  defp claim(conn), do: conn |> get_session() |> SessionAuthority.claim()

  defp other_lineage, do: SessionAuthority.bootstrap().lineage

  defp auction! do
    "Gate bid preparation"
    |> Autolaunch.import_auction!(nil, false, :active, ~U[2026-07-31 11:00:00Z], actor: %System{})
    |> Autolaunch.set_auction_bid_terms!(@auction_address, @quote_token, "QUOTE", 6, "2.5",
      actor: %System{}
    )
  end

  defp put_valid_csrf(conn) do
    token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
    |> put_session("_csrf_token", Plug.CSRFProtection.dump_state())
    |> put_req_header("x-csrf-token", token)
  end
end
