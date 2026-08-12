defmodule AshPlatformWeb.PrivySessionControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  @logout_epoch_cookie "_ash_platform_logout_epoch"

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Formation

  test "verified Privy evidence creates and renews a canonical local session", %{conn: conn} do
    visitor = conn |> init_test_session(%{visitor: "discard-me"}) |> csrf_bootstrap()
    visitor_cookie = session_cookie(visitor)
    csrf = json_response(visitor, 200)["csrf_token"]

    signed_in =
      visitor
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("authorization", "Bearer valid")
      |> put_req_header("x-csrf-token", csrf)
      |> post("/auth/privy/session", %{
        privy_user_id: "did:privy:forged",
        wallet_address: "0x2222222222222222222222222222222222222222",
        display_name: "Forged",
        role: "admin"
      })

    payload = json_response(signed_in, 200)
    assert payload["authenticated"] == true
    assert get_resp_header(signed_in, "x-ash-session-changed") == ["true"]
    assert payload["account_control"]["profile_path"] == nil

    assert payload["account_control"]["avatar_data_uri"] =~
             "data:image/svg+xml;base64,"

    assert signed_in.private[:plug_session_info] == :renew
    assert session_cookie(signed_in) != visitor_cookie

    assert get_session(signed_in) |> Map.keys() |> Enum.sort() == [
             "human_account_id",
             "live_socket_id"
           ]

    assert_canonical_live_socket_id(get_session(signed_in, :live_socket_id))

    assert {:ok, account} =
             Accounts.get_by_privy_did("did:privy:verified", actor: %System{})

    assert account.wallet_address == "0x1111111111111111111111111111111111111111"
    assert account.display_name == nil
  end

  test "missing, invalid, and wrong-token-type bearers are rejected before a write", %{conn: conn} do
    assert {:ok, before_attempts} =
             Accounts.get_by_privy_did("did:privy:verified", actor: %System{})

    for header <- [nil, "Bearer invalid", "Bearer identity-token", "Bearer missing-sid"] do
      request = conn |> init_test_session(%{}) |> put_valid_csrf()
      request = if header, do: put_req_header(request, "authorization", header), else: request
      assert request |> post("/auth/privy/session", %{}) |> json_response(401)
    end

    assert {:ok, after_attempts} =
             Accounts.get_by_privy_did("did:privy:verified", actor: %System{})

    assert account_evidence(after_attempts) == account_evidence(before_attempts)
  end

  test "verified registration is idempotent under concurrent attempts" do
    verified = %AshPlatform.VerifiedPrivyIdentity{
      privy_user_id: "did:privy:concurrent",
      session_id: "concurrent-session",
      wallet_address: "0x3333333333333333333333333333333333333333",
      wallet_addresses: ["0x3333333333333333333333333333333333333333"]
    }

    results =
      1..2
      |> Task.async_stream(fn _ -> AshPlatform.Accounts.VerifiedSession.establish(verified) end,
        max_concurrency: 2,
        ordered: false
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _, []}}, &1))
    assert {:ok, account} = Accounts.get_by_privy_did("did:privy:concurrent", actor: %System{})
    assert account.wallet_address == verified.wallet_address
  end

  test "session inspection exposes Profile only from the account's canonical Regent", %{
    conn: conn
  } do
    wallet = "0x1111111111111111111111111111111111111111"

    assert {:ok, account} =
             Accounts.register_verified("did:privy:u3-profile", wallet, [wallet],
               actor: %System{}
             )

    assert {:ok, _regent} =
             Formation.form_regent("u3-profile", "U3 Profile",
               actor: %Human{human_account_id: account.id}
             )

    payload =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> get("/auth/session")
      |> json_response(200)

    assert payload["account_control"]["profile_path"] == "/regents/u3-profile"
    assert payload["account_control"]["label"] == "U3 Profile"
  end

  test "an upsert conflict without linked accounts cannot erase wallet evidence" do
    actor = %System{}
    wallet = "0x4444444444444444444444444444444444444444"

    assert {:ok, _account} =
             Accounts.register_verified("did:privy:wallet-race", wallet, [wallet], actor: actor)

    assert {:ok, _account} =
             Accounts.register_verified("did:privy:wallet-race", nil, [], actor: actor)

    assert {:ok, account} =
             Accounts.get_by_privy_did("did:privy:wallet-race", actor: actor)

    assert account.wallet_address == wallet
    assert account.wallet_addresses == [wallet]
  end

  test "CSRF is required for both session creation and deletion", %{conn: conn} do
    assert_error_sent 403, fn ->
      conn
      |> init_test_session(%{})
      |> enforce_csrf()
      |> put_req_header("authorization", "Bearer valid")
      |> post("/auth/privy/session", %{})
    end

    assert_error_sent 403, fn ->
      conn
      |> init_test_session(%{human_account_id: 42})
      |> enforce_csrf()
      |> delete("/auth/privy/session")
    end
  end

  test "session inspection is cookie-only and logout drops the local session", %{conn: conn} do
    anonymous =
      conn
      |> put_req_header("authorization", "Bearer valid")
      |> get("/auth/session")
      |> json_response(200)

    assert anonymous["authenticated"] == false
    assert anonymous["account_control"]["kind"] == "sign_in"

    deleted =
      conn
      |> init_test_session(%{human_account_id: 42})
      |> put_valid_csrf()
      |> delete("/auth/privy/session")

    assert %{"ok" => true} = json_response(deleted, 200)
    assert deleted.private[:plug_session_info] == :drop

    logout_epoch_cookie =
      deleted
      |> get_resp_header("set-cookie")
      |> Enum.find(&String.contains?(&1, @logout_epoch_cookie <> "="))

    assert logout_epoch_cookie =~ "; HttpOnly"
    assert logout_epoch_cookie =~ "; SameSite=Lax"
  end

  test "logout is idempotent without an authenticated cookie when CSRF is valid", %{conn: conn} do
    deleted =
      conn
      |> init_test_session(%{visitor: "discard-me"})
      |> put_valid_csrf()
      |> delete("/auth/privy/session")

    assert %{"ok" => true} = json_response(deleted, 200)
    assert deleted.private[:plug_session_info] == :drop
    assert get_session(deleted) == %{}
  end

  test "logout disconnects an already-open Formation LiveView", %{conn: conn} do
    signed_in =
      conn
      |> init_test_session(%{})
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer valid")
      |> post("/auth/privy/session", %{})

    assert %{"authenticated" => true} = json_response(signed_in, 200)

    live_socket_id = get_session(signed_in, :live_socket_id)
    AshPlatformWeb.Endpoint.subscribe(live_socket_id)
    {:ok, view, _html} = signed_in |> recycle() |> live("/formation")
    assert Process.alive?(view.pid)
    flush_test_messages()

    deleted =
      build_conn()
      |> init_test_session(get_session(signed_in))
      |> put_valid_csrf()
      |> delete("/auth/privy/session")

    assert_response_sent_then_disconnect(live_socket_id)

    assert %{"ok" => true} = json_response(deleted, 200)
  end

  test "stale-epoch logout sends the dropped-session response before one disconnect", %{
    conn: conn
  } do
    conn
    |> init_test_session(%{})
    |> put_valid_csrf()
    |> put_req_header("authorization", "Bearer valid")
    |> post("/auth/privy/session", %{})

    assert {:ok, account} = Accounts.get_by_privy_did("did:privy:verified", actor: %System{})
    live_socket_id = canonical_live_socket_id()
    AshPlatformWeb.Endpoint.subscribe(live_socket_id)
    flush_test_messages()

    deleted =
      build_conn()
      |> put_req_cookie(@logout_epoch_cookie, "current-epoch")
      |> init_test_session(%{
        human_account_id: account.id,
        live_socket_id: live_socket_id,
        privy_logout_epoch: "stale-epoch"
      })
      |> put_valid_csrf()
      |> delete("/auth/privy/session")

    assert_response_sent_then_disconnect(live_socket_id)

    refute_receive %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"}
    assert %{"ok" => true} = json_response(deleted, 200)
    assert deleted.private[:plug_session_info] == :drop
  end

  test "canonical same-account refresh preserves the mounted Formation LiveView session", %{
    conn: conn
  } do
    signed_in =
      conn
      |> init_test_session(%{})
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer valid")
      |> post("/auth/privy/session", %{})

    assert %{"authenticated" => true} = json_response(signed_in, 200)

    previous_socket_id = get_session(signed_in, :live_socket_id)
    previous_account_id = get_session(signed_in, :human_account_id)
    AshPlatformWeb.Endpoint.subscribe(previous_socket_id)
    {:ok, view, _html} = signed_in |> recycle() |> live("/formation")
    assert Process.alive?(view.pid)

    refresh_request =
      build_conn()
      |> init_test_session(get_session(signed_in))
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer valid")

    expected_session = get_session(refresh_request)
    refreshed = post(refresh_request, "/auth/privy/session", %{})

    assert %{"authenticated" => true} = json_response(refreshed, 200)
    assert get_resp_header(refreshed, "x-ash-session-changed") == ["false"]
    assert get_session(refreshed, :human_account_id) == previous_account_id
    assert get_session(refreshed) == expected_session
    assert get_session(refreshed, :live_socket_id) == previous_socket_id
    refute refreshed.private[:plug_session_info] in [:renew, :drop]

    refute_receive %Phoenix.Socket.Broadcast{
      topic: ^previous_socket_id,
      event: "disconnect"
    }

    assert Process.alive?(view.pid)

    assert render_click(view, "refresh_verified_connections", %{}) =~
             "Run your Regent in Nous Portal"
  end

  test "same-account refresh renews every incomplete socket form without broadcasting it", %{
    conn: conn
  } do
    signed_in =
      conn
      |> init_test_session(%{})
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer valid")
      |> post("/auth/privy/session", %{})

    account_id = get_session(signed_in, :human_account_id)
    canonical_token = Base.url_encode64(:binary.copy(<<0>>, 32), padding: false)

    malformed_socket_ids = [
      nil,
      "",
      "privy_sessions:",
      "privy_sessions:short",
      "privy_sessions:" <> String.duplicate("a", 43),
      "privy_sessions:" <> String.duplicate("+", 43),
      "privy_sessions:" <> Base.url_encode64(:binary.copy(<<0>>, 31), padding: false),
      "privy_sessions:" <> canonical_token <> "="
    ]

    for malformed_socket_id <- malformed_socket_ids do
      if malformed_socket_id, do: AshPlatformWeb.Endpoint.subscribe(malformed_socket_id)

      refreshed =
        build_conn()
        |> init_test_session(%{
          human_account_id: account_id,
          live_socket_id: malformed_socket_id,
          unrelated: "discard-me"
        })
        |> put_valid_csrf()
        |> put_req_header("authorization", "Bearer valid")
        |> post("/auth/privy/session", %{})

      assert %{"authenticated" => true} = json_response(refreshed, 200)
      assert get_resp_header(refreshed, "x-ash-session-changed") == ["true"]
      assert refreshed.private[:plug_session_info] == :renew
      assert_canonical_live_socket_id(get_session(refreshed, :live_socket_id))
      refute get_session(refreshed, :live_socket_id) == malformed_socket_id
      refute get_session(refreshed, :unrelated)

      if malformed_socket_id do
        refute_receive %Phoenix.Socket.Broadcast{
          topic: ^malformed_socket_id,
          event: "disconnect"
        }
      end
    end
  end

  test "the current logout epoch rejects a late pre-logout session and admits a fresh sign-in", %{
    conn: conn
  } do
    wallet = "0x7777777777777777777777777777777777777777"

    assert {:ok, account} =
             Accounts.register_verified("did:privy:logout-epoch", wallet, [wallet],
               actor: %System{}
             )

    live_socket_id = "privy_sessions:superseded"
    AshPlatformWeb.Endpoint.subscribe(live_socket_id)

    superseded =
      conn
      |> put_req_cookie(@logout_epoch_cookie, "current-epoch")
      |> init_test_session(%{
        human_account_id: account.id,
        live_socket_id: live_socket_id,
        privy_logout_epoch: "pre-logout-epoch"
      })
      |> get("/auth/session")

    assert %{"authenticated" => false} = json_response(superseded, 200)
    assert superseded.private[:plug_session_info] == :drop

    refute_receive %Phoenix.Socket.Broadcast{
      topic: ^live_socket_id,
      event: "disconnect"
    }

    fresh =
      build_conn()
      |> put_req_cookie(@logout_epoch_cookie, "current-epoch")
      |> init_test_session(%{})
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer valid")
      |> post("/auth/privy/session", %{})

    assert %{"authenticated" => true} = json_response(fresh, 200)
    assert get_session(fresh, :privy_logout_epoch) == "current-epoch"
  end

  test "SIWA headers cannot enter the browser-human rail", %{conn: conn} do
    response =
      conn
      |> init_test_session(%{})
      |> put_valid_csrf()
      |> put_req_header("x-regent-siwa-receipt", "signed-agent-receipt")
      |> post("/auth/privy/session", %{})

    assert %{"error" => "unauthorized"} = json_response(response, 401)
  end

  test "session cookies are HTTP-only locally and secure under production options", %{conn: conn} do
    original = Application.fetch_env!(:ash_platform, :session_options)
    on_exit(fn -> Application.put_env(:ash_platform, :session_options, original) end)

    local_cookie = conn |> init_test_session(%{}) |> csrf_bootstrap() |> session_cookie()
    assert local_cookie =~ "; HttpOnly"
    refute String.downcase(local_cookie) =~ "; secure"

    Application.put_env(
      :ash_platform,
      :session_options,
      Keyword.merge(original, secure: true, http_only: true)
    )

    secure_cookie = build_conn() |> init_test_session(%{}) |> csrf_bootstrap() |> session_cookie()
    assert secure_cookie =~ "; HttpOnly"
    assert String.downcase(secure_cookie) =~ "; secure"
  end

  test "missing current linked-wallet evidence invalidates the account and local session", %{
    conn: conn
  } do
    valid =
      conn
      |> init_test_session(%{})
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer valid")
      |> post("/auth/privy/session", %{})

    assert {:ok, account} = Accounts.get_by_privy_did("did:privy:verified", actor: %System{})

    rejected =
      build_conn()
      |> init_test_session(%{human_account_id: account.id})
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer no-wallet")
      |> post("/auth/privy/session", %{})

    assert %{"error" => "unauthorized"} = json_response(rejected, 401)
    assert rejected.private[:plug_session_info] == :drop
    assert get_session(rejected) == %{}

    assert {:ok, invalidated} =
             Accounts.get_by_privy_did("did:privy:verified", actor: %System{})

    assert invalidated.wallet_address == nil
    assert invalidated.wallet_addresses == []

    stale_cookie =
      build_conn()
      |> init_test_session(%{human_account_id: account.id})
      |> get("/auth/session")

    assert %{"authenticated" => false} = json_response(stale_cookie, 200)
    assert stale_cookie.private[:plug_session_info] == :drop
    assert get_session(stale_cookie) == %{}
    assert json_response(valid, 200)["authenticated"] == true
  end

  test "provider and server account mismatch replaces the local session deterministically", %{
    conn: conn
  } do
    conn
    |> init_test_session(%{})
    |> put_valid_csrf()
    |> put_req_header("authorization", "Bearer valid")
    |> post("/auth/privy/session", %{})

    assert {:ok, former} = Accounts.get_by_privy_did("did:privy:verified", actor: %System{})

    former_socket_id = canonical_live_socket_id()
    AshPlatformWeb.Endpoint.subscribe(former_socket_id)

    replaced =
      build_conn()
      |> init_test_session(%{human_account_id: former.id, live_socket_id: former_socket_id})
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer other-account")
      |> post("/auth/privy/session", %{})

    assert %{"authenticated" => true} = json_response(replaced, 200)
    assert get_resp_header(replaced, "x-ash-session-changed") == ["true"]

    assert {:ok, current} = Accounts.get_by_privy_did("did:privy:other", actor: %System{})
    assert current.id != former.id
    assert get_session(replaced, :human_account_id) == current.id

    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^former_socket_id,
      event: "disconnect"
    }
  end

  test "current provider evidence refreshes a stale former wallet without changing identity", %{
    conn: conn
  } do
    conn
    |> init_test_session(%{})
    |> put_valid_csrf()
    |> put_req_header("authorization", "Bearer valid")
    |> post("/auth/privy/session", %{})

    assert {:ok, account} = Accounts.get_by_privy_did("did:privy:verified", actor: %System{})

    live_socket_id = canonical_live_socket_id()

    refreshed =
      build_conn()
      |> init_test_session(%{
        human_account_id: account.id,
        live_socket_id: live_socket_id,
        preserved: "session-state"
      })
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer changed-wallet")
      |> post("/auth/privy/session", %{})

    assert %{"authenticated" => true} = json_response(refreshed, 200)
    assert get_resp_header(refreshed, "x-ash-session-changed") == ["false"]
    assert get_session(refreshed, :live_socket_id) == live_socket_id
    assert get_session(refreshed, :preserved) == "session-state"

    assert {:ok, current} = Accounts.get_by_privy_did("did:privy:verified", actor: %System{})
    assert current.id == account.id
    assert current.wallet_address == "0x2222222222222222222222222222222222222222"
    assert current.wallet_addresses == ["0x2222222222222222222222222222222222222222"]
  end

  test "a social account conflict preserves login and reports a connection error", %{conn: conn} do
    owner =
      Accounts.register_verified!(
        "did:privy:conflict-owner",
        nil,
        [],
        actor: %System{}
      )

    assert {:ok, _identity} =
             Accounts.upsert_linked_identity(
               :x,
               "shared-x-subject",
               "owner",
               nil,
               DateTime.utc_now(),
               %{},
               owner.id,
               actor: %System{}
             )

    response =
      conn
      |> init_test_session(%{})
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer conflicting-social")
      |> post("/auth/privy/session", %{})

    assert %{"authenticated" => true} = json_response(response, 200)
    assert get_resp_header(response, "x-ash-identity-error") == ["already-connected"]

    account =
      Accounts.get_by_privy_did!("did:privy:conflicting-social", actor: %System{})

    assert get_session(response, :human_account_id) == account.id

    assert {:ok, []} =
             Accounts.list_linked_identities_for_account(account.id, actor: %System{})

    live_socket_id = get_session(response, :live_socket_id)
    AshPlatformWeb.Endpoint.subscribe(live_socket_id)

    refresh_request =
      build_conn()
      |> init_test_session(get_session(response))
      |> put_valid_csrf()
      |> put_req_header("authorization", "Bearer conflicting-social")

    expected_session = get_session(refresh_request)
    refreshed = post(refresh_request, "/auth/privy/session", %{})

    assert %{"authenticated" => true} = json_response(refreshed, 200)
    assert get_resp_header(refreshed, "x-ash-identity-error") == ["already-connected"]
    assert get_resp_header(refreshed, "x-ash-session-changed") == ["false"]
    assert get_session(refreshed) == expected_session
    refute_receive %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"}
  end

  defp csrf_bootstrap(conn), do: get(conn, "/auth/csrf")

  defp put_valid_csrf(conn) do
    token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> enforce_csrf()
    |> put_session("_csrf_token", Plug.CSRFProtection.dump_state())
    |> put_req_header("x-csrf-token", token)
  end

  defp enforce_csrf(conn),
    do: %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}

  defp session_cookie(conn) do
    conn |> get_resp_header("set-cookie") |> Enum.find(&String.contains?(&1, "_ash_platform_key"))
  end

  defp canonical_live_socket_id do
    "privy_sessions:" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  defp assert_canonical_live_socket_id("privy_sessions:" <> token) do
    assert byte_size(token) == 43
    assert {:ok, decoded} = Base.url_decode64(token, padding: false)
    assert byte_size(decoded) == 32
    assert Base.url_encode64(decoded, padding: false) == token
  end

  defp flush_test_messages do
    receive do
      _message -> flush_test_messages()
    after
      0 -> :ok
    end
  end

  defp assert_response_sent_then_disconnect(live_socket_id) do
    events = receive_until_disconnect(live_socket_id, [])
    assert events == [:response_sent, :socket_disconnect]
  end

  defp receive_until_disconnect(live_socket_id, events) do
    receive do
      {:plug_conn, :sent} ->
        receive_until_disconnect(live_socket_id, [:response_sent | events])

      %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"} ->
        Enum.reverse([:socket_disconnect | events])

      _message ->
        receive_until_disconnect(live_socket_id, events)
    after
      100 -> flunk("expected response send followed by socket disconnect")
    end
  end

  defp account_evidence(nil), do: nil

  defp account_evidence(account) do
    Map.take(account, [:id, :privy_user_id, :wallet_address, :wallet_addresses, :display_name])
  end
end
