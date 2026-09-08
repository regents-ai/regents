defmodule AshPlatformWeb.ShowcaseTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint AshPlatformWeb.Endpoint
  alias AshPlatformWeb.Showcase.{Catalog, LocalOnly, Sample, Utilities}

  defp local_conn do
    build_conn()
    |> Map.put(:host, "localhost")
    |> put_private(:live_view_connect_info, %{
      peer_data: %{address: {127, 0, 0, 1}},
      uri: URI.parse("http://localhost/showcase")
    })
  end

  test "HTTP pages and machine inventory are loopback-only, without trusting forwarding headers" do
    for path <-
          ~w(/showcase /showcase/catalog /showcase/style.css /showcase/preview /showcase/privy) do
      for {host, peer} <- [{"example.com", {127, 0, 0, 1}}, {"localhost", {192, 0, 2, 1}}] do
        conn =
          build_conn()
          |> Map.put(:host, host)
          |> Map.put(:remote_ip, peer)
          |> put_req_header("x-forwarded-for", "127.0.0.1")
          |> put_req_header("x-forwarded-host", "localhost")
          |> get(path)

        assert response(conn, 404) == "Not found"
      end
    end

    conn = local_conn() |> get("/showcase/catalog")
    assert json_response(conn, 200)["components"] != []
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    reference = local_conn() |> get("/showcase/privy")
    assert html_response(reference, 200) =~ "Privy integration"
    assert get_resp_header(reference, "cache-control") == ["no-store"]
    assert LocalOnly.allowed?({0, 0, 0, 0, 0, 0, 0, 1}, "::1")
    refute LocalOnly.allowed?(nil, "localhost")
  end

  test "connected mount refuses remote and missing transport evidence" do
    for info <- [
          %{},
          %{peer_data: %{address: {192, 0, 2, 1}}, uri: URI.parse("http://localhost")},
          %{peer_data: %{address: {127, 0, 0, 1}}, uri: URI.parse("http://example.com")}
        ] do
      conn = local_conn() |> put_private(:live_view_connect_info, info)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/showcase")
    end
  end

  test "gallery connects, creates local Ash records, validates, and runs utilities" do
    {:ok, view, html} = live(local_conn(), "/showcase")
    assert html =~ "Shared foundations."
    assert has_element?(view, "input[type=color]")
    assert has_element?(view, "input[data-sc-shimmer-color][type=color]")
    assert has_element?(view, "#capabilities article.rg-feature", "Clear boundaries")
    assert has_element?(view, "#capabilities img[alt='Regents crown']")
    assert has_element?(view, "#staking-ratio", "56.2%")
    assert has_element?(view, "#staking-ratio", "43.8%")
    view |> form("#ratio-preview", ratio: %{state: "unavailable"}) |> render_change()
    assert has_element?(view, "#staking-ratio", "No data")
    view |> form("#ratio-preview", ratio: %{state: "full"}) |> render_change()
    assert has_element?(view, "#staking-ratio", "100%")
    view |> form("#ratio-preview", ratio: %{state: "sample"}) |> render_change()
    assert has_element?(view, "#staking-ratio", "56.2%")

    view |> element("button", "Create item") |> render_click()
    assert has_element?(view, "#empty-state-items", "Workshop item 1")
    refute has_element?(view, "#empty-state-demo", "Nothing here yet.")
    view |> element("#empty-state-demo button", "Add item") |> render_click()
    assert has_element?(view, "#empty-state-items", "Workshop item 2")
    view |> element("#empty-state-demo button", "Reset items") |> render_click()
    assert has_element?(view, "#empty-state-demo", "Nothing here yet.")

    view |> element("#showcase-chamber button", "Edit") |> render_click()
    assert has_element?(view, "#chamber-form")
    view |> form("#chamber-form", chamber: %{title: "x"}) |> render_submit()
    assert has_element?(view, "#chamber-title[aria-invalid=true][value=x]")
    view |> form("#chamber-form", chamber: %{title: "Revised step"}) |> render_submit()
    assert has_element?(view, "#showcase-chamber", "Revised step")
    refute has_element?(view, "#chamber-form")
    view |> element("#showcase-chamber button", "Edit") |> render_click()
    view |> element("#chamber-form button", "Cancel") |> render_click()
    assert has_element?(view, "#showcase-chamber", "Revised step")
    refute has_element?(view, "#chamber-form")

    assert has_element?(view, "#showcase-ledger [data-sc-copy=showcase-ledger-content]")

    assert has_element?(view, "[data-sc-privy-mode=fixture]", "Real sign-in is unavailable")
    assert has_element?(view, "[data-sc-privy-mode=fixture] button[disabled]", "Connect Privy")
    refute has_element?(view, "#account-control [data-account-target]")

    assert view
           |> form("#sample-form", sample: %{title: "Demo record", quantity: "2"})
           |> render_submit() =~ "Demo record × 2"

    assert view |> form("#sample-form", sample: %{title: "x", quantity: "0"}) |> render_submit() =~
             "aria-invalid=\"true\""

    assert view
           |> form("#utility-form", kind: "amount", amount: "1000000000000000000", decimals: "18")
           |> render_submit() =~ "formatted"

    view |> form("#comment-form", comment: %{body: "   "}) |> render_submit()
    assert has_element?(view, "#comment-ledger-status[role=alert]", "could not be posted")
    refute has_element?(view, ".comment-ledger__list")

    assert view |> form("#comment-form", comment: %{body: "Fixture comment"}) |> render_submit() =~
             "Fixture comment"

    assert has_element?(view, "#comment-ledger-status[role=status]", "Comment posted")

    assert view |> element("#showcase-connections-github button") |> render_click() =~
             "No provider request"
  end

  test "active component inventory names exported functions and their attributes" do
    for {module, names} <- Catalog.registry() do
      Code.ensure_loaded!(module)
      for name <- names, do: assert(function_exported?(module, name, 1))
    end

    assert Enum.any?(Catalog.components(), &(&1.function == "field" and "label" in &1.attributes))

    assert Enum.any?(
             Catalog.components(),
             &(&1.function == "capability_card" and "media" in &1.slots)
           )
  end

  test "Ash sample validation uses no persistent data layer" do
    assert Ash.Resource.Info.data_layer(Sample) == Ash.DataLayer.Simple

    assert {:ok, %{title: "Valid", quantity: 2}} = create_sample(%{title: "Valid", quantity: 2})
    assert {:error, _} = create_sample(%{title: "x", quantity: 1})
    assert {:error, _} = create_sample(%{title: "Valid", quantity: 101})
    assert {:error, _} = create_sample(%{quantity: 1})
  end

  defp create_sample(params),
    do: Sample |> Ash.Changeset.for_create(:create, params) |> Ash.create()

  test "utility examples preserve numeric precision and reject invalid input" do
    address = "0x1111111111111111111111111111111111111111"
    assert %{canonical: ^address} = Utilities.address(address)
    assert %{error: _} = Utilities.address("not an address")
    assert %{formatted: "1"} = Utilities.amount("1000000000000000000", "18")
    assert %{formatted: "0.000001"} = Utilities.amount("1", "6")

    for {value, decimals} <- [{"-1", "18"}, {"1", "37"}, {String.duplicate("9", 1000), "18"}],
        do: assert(%{error: _} = Utilities.amount(value, decimals))

    assert %{data: data} = Utilities.calldata(address, "1")
    assert String.starts_with?(data, "0x095ea7b3")
    assert byte_size(data) == 138
    assert %{error: _} = Utilities.calldata(address, to_string(Integer.pow(2, 256)))
  end

  test "Privy fixture verifies actual signatures and rejects expiry and audience" do
    assert %{result: "Verified fixture", session_created: false} = Utilities.privy(:valid)
    assert %{reason: :token_expired} = Utilities.privy(:expired)
    assert %{reason: :invalid_audience} = Utilities.privy(:audience)
  end
end
