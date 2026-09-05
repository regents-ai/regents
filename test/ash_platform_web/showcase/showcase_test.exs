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
          ~w(/showcase /showcase/catalog /showcase/style.css /showcase/sigils.svg /showcase/preview) do
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

    assert view
           |> form("#sample-form", sample: %{title: "Demo record", quantity: "2"})
           |> render_submit() =~ "Demo record × 2"

    assert view |> form("#sample-form", sample: %{title: "x", quantity: "0"}) |> render_submit() =~
             "aria-invalid=\"true\""

    assert view
           |> form("#utility-form", kind: "amount", amount: "1000000000000000000", decimals: "18")
           |> render_submit() =~ "formatted"

    assert view |> form("#comment-form", comment: %{body: "Fixture comment"}) |> render_submit() =~
             "Fixture comment"

    assert view |> element("#showcase-connections-github button") |> render_click() =~
             "No provider request"
  end

  test "every exported design component is in the visual inventory" do
    for {module, names} <- Catalog.registry() do
      Code.ensure_loaded!(module)

      exported =
        module.__components__()
        |> Enum.filter(fn {_, metadata} -> metadata.kind == :def end)
        |> Enum.map(&elem(&1, 0))
        |> MapSet.new()

      # Embedded templates have no declarative attr/slot metadata.
      assert MapSet.subset?(exported, MapSet.new(names)), inspect(module)
      for name <- names, do: assert(function_exported?(module, name, 1))
    end

    aliases = [Regent.Surface, Regent.Chamber, Regent.Ledger, Regent.Sigil]

    shared_modules =
      Application.spec(:regent_ui, :modules)
      |> Enum.filter(fn module ->
        Code.ensure_loaded?(module) and function_exported?(module, :__components__, 0)
      end)

    covered_modules = Enum.map(Catalog.registry(), &elem(&1, 0)) ++ aliases
    assert MapSet.subset?(MapSet.new(shared_modules), MapSet.new(covered_modules))
    assert Enum.any?(Catalog.components(), &(&1.function == "field" and "label" in &1.attributes))
  end

  test "Ash sample validation uses no persistent data layer" do
    assert Ash.Resource.Info.data_layer(Sample) == Ash.DataLayer.Simple

    assert {:ok, %{title: "Valid", quantity: 2}} =
             Sample
             |> Ash.Changeset.for_create(:create, %{title: "Valid", quantity: 2})
             |> Ash.create(authorize?: false)

    for params <- [%{title: "x", quantity: 1}, %{title: "Valid", quantity: 101}, %{quantity: 1}] do
      assert {:error, _} =
               Sample
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create(authorize?: false)
    end
  end

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
