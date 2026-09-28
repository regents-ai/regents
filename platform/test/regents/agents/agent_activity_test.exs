defmodule Regents.Agents.AgentActivityTest do
  use ExUnit.Case, async: true

  alias Regents.Agents.{AgentActivity, PairedAgent}

  @wallet "0x2222222222222222222222222222222222222222"
  @paired_at ~U[2026-09-26 15:00:00.000000Z]

  test "an agent's requests across the Regents sites read as plain actions after its pairing" do
    Req.Test.expect(Regents.Siwa, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/shared/siwa/activity"

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Bearer test-activity-read-token"
             ]

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "wallet_address" => @wallet,
               "since" => "2026-09-26T15:00:00.000000Z"
             }

      Req.Test.json(conn, %{
        "data" => %{
          "activity" => [
            request("patchbay", "POST", "/api/agent/reports", "2026-09-26T15:09:00Z"),
            request("autolaunch", "GET", "/v1/agent/launches", "2026-09-26T15:08:00Z"),
            request("elsewhere", "POST", "/anything", "2026-09-26T15:07:00Z"),
            request("regents", "GET", "/api/agents/v1/me", "2026-09-26T15:06:00Z"),
            request("regents", "POST", "/api/agents/v1/pair", "2026-09-26T15:05:00Z")
          ]
        }
      })
    end)

    assert {:ok, activity} = AgentActivity.recent(agent())

    assert Enum.map(activity, &{&1.site, &1.action}) == [
             {"Patchbay", "Asked to make a change"},
             {"Autolaunch", "Looked something up"},
             {"Regents Labs", "Checked in"},
             {"Regents Labs", "Paired with your account"}
           ]

    assert hd(activity).occurred_at == ~U[2026-09-26 15:09:00Z]
    assert List.last(activity).occurred_at == @paired_at
  end

  test "a refused or unreachable read is an error, not an empty history" do
    Req.Test.expect(Regents.Siwa, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => %{}})
    end)

    assert {:error, {:unexpected_status, 401}} = AgentActivity.recent(agent())

    Req.Test.expect(Regents.Siwa, &Req.Test.transport_error(&1, :econnrefused))
    assert {:error, %Req.TransportError{}} = AgentActivity.recent(agent())
  end

  defp request(audience, method, path, at),
    do: %{"audience" => audience, "method" => method, "path" => path, "occurred_at" => at}

  defp agent, do: %PairedAgent{wallet: @wallet, paired_at: @paired_at}
end
