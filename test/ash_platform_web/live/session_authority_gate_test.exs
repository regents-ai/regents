defmodule AshPlatformWeb.Live.SessionAuthorityGateTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch

  @wallet "0x1111111111111111111111111111111111111111"
  @auction_address "0x3333333333333333333333333333333333333333"
  @quote_token "0x4444444444444444444444444444444444444444"
  @profile "#account-control [data-account-target=profile]"
  @sign_in "#account-control [data-account-target=sign-in]"
  @signed_in_markup ~s(data-account-target="sign-out")

  test "CANONICAL_AUTHORITY_ROW: the signed static token carries no credential", %{conn: conn} do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})
    %{"session_lineage" => lineage, "live_socket_id" => cookie_topic} = get_session(signed_in)

    markup = html_response(get(signed_in, "/formation"), 200)

    # Phoenix.LiveView.Static signs this token with Phoenix.Token, which is
    # integrity-only: anyone holding the markup can read what it carries.
    assert %{session: session} = static_session!(markup)

    assert session == %{
             "render_topic" => SessionAuthority.topic(lineage),
             "render_route" => "/formation"
           }

    refute markup =~ lineage
    refute markup =~ Base.encode64(lineage)
    refute markup =~ Base.encode16(:crypto.hash(:sha256, lineage))

    for credential <- ["session_lineage", "session_generation", "live_socket_id"] do
      refute Map.has_key?(session, credential)
    end

    # The topic it does carry is the one the cookie already names publicly.
    assert session["render_topic"] == cookie_topic
  end

  test "CANONICAL_AUTHORITY_ROW: an anonymous render signs only its route" do
    assert %{session: %{"render_route" => "/formation"} = session} =
             build_conn() |> get("/formation") |> html_response(200) |> static_session!()

    assert Map.keys(session) == ["render_route"]
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

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: an invalid handshake is refused onto the public root",
       %{
         conn: conn
       } do
    account = account!()
    signed_in = init_test_session(conn, %{human_account_id: account.id})
    current = get_session(signed_in)

    for handshake <- [
          # stale, ahead of the row, malformed topic, malformed shape, and the
          # handshake a page that named a lineage must never mount without.
          %{current | "session_generation" => current["session_generation"] - 1},
          %{current | "session_generation" => current["session_generation"] + 1},
          %{current | "live_socket_id" => SessionAuthority.topic(other_lineage())},
          Map.delete(current, "live_socket_id"),
          %{}
        ] do
      assert {:error, {:redirect, %{to: "/"}}} =
               signed_in |> connects_with(handshake) |> live("/formation")
    end

    static = get(signed_in, "/formation")
    assert SessionAuthority.revoke(claim(signed_in))

    assert {:error, {:redirect, %{to: "/"}}} = static |> connects_with(current) |> live()
  end

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: a claim-shaped handshake under an anonymous render is refused" do
    signed_in = init_test_session(build_conn(), %{human_account_id: account!().id})
    current = get_session(signed_in)
    assert SessionAuthority.revoke(claim(signed_in))

    # The render names no lineage, but the handshake still asserts one.
    anonymous = get(build_conn(), "/formation")
    refute html_response(anonymous, 200) =~ @signed_in_markup

    assert {:error, {:redirect, %{to: "/"}}} = anonymous |> connects_with(current) |> live()

    assert {:error, {:redirect, %{to: "/"}}} =
             anonymous |> connects_with(%{"session_lineage" => "not-a-lineage"}) |> live()
  end

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: a current handshake under an anonymous render reloads the route",
       %{conn: conn} do
    browser = init_test_session(conn, %{human_account_id: account!().id})

    # The page was fetched without the cookie the socket then connects with.
    anonymous = get(build_conn(), "/formation")

    assert {:error, {:redirect, %{to: "/formation"}}} =
             anonymous |> connects_with(get_session(browser)) |> live()

    # The realigned request names that lineage, so the next mount accepts it.
    {:ok, view, _html} = live(browser, "/formation")
    assert has_element?(view, @profile)
  end

  test "HANDSHAKE_IS_CONNECTED_AUTHORITY: a handshake and render with no claim mount anonymous" do
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

    # The revoked lease halts navigation at the authority hook itself.
    assert {:error, {:redirect, %{to: "/"}}} = render_patch(view, "/formation")
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

    # /formation renders for anonymous visitors, so only the authority hook can
    # be refusing this navigation.
    assert {:error, {:redirect, %{to: "/"}}} = render_patch(view, "/formation")
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

    # The browser still holds the revoked claim, so its reconnect is refused
    # rather than quietly downgraded.
    assert {:error, {:redirect, %{to: "/"}}} = live(signed_in, "/formation")
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

  # Verifies the token exactly as Phoenix.LiveView.Static does: Phoenix.Token
  # over the endpoint's live_view signing salt, wrapping {token_vsn, data}.
  defp static_session!(markup) do
    [_match, token] = Regex.run(~r/data-phx-session="([^"]+)"/, markup)
    salt = AshPlatformWeb.Endpoint.config(:live_view)[:signing_salt]

    {:ok, {_version, data}} =
      Phoenix.Token.verify(AshPlatformWeb.Endpoint, salt, token, max_age: 1_209_600)

    data
  end

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
