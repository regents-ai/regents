defmodule RegentsWeb.AgentNamesTest do
  @moduledoc """
  A paired agent checks and claims a free Regent Name for its person. Invariants:
  a claim spends one of the person's own free claims and records the name for
  their wallet; a refused claim records and spends nothing; only an agent with
  the current pairing may claim.
  """
  use RegentsWeb.ConnCase, async: false

  import Regents.NamesFixtures

  alias RegentAgents.Person
  alias Regents.Accounts
  alias Regents.Actors.System
  alias Regents.Repo

  @agent_wallet "0x2323232323232323232323232323232323232323"

  setup_all do
    ensure_claims_table!()
  end

  setup %{conn: conn} do
    Regents.RateLimiter.reset()
    on_exit(&Regents.RateLimiter.reset/0)

    unique = Elixir.System.unique_integer([:positive])
    wallet = "0x" <> String.pad_leading(Integer.to_string(unique, 16), 40, "0")
    did = "did:privy:agent-names:#{unique}"
    Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    person = %Person{privy_user_id: did}

    siwa_verifies(@agent_wallet)
    issued = RegentAgents.issue_pairing_code!(actor: person)

    assert conn
           |> put_req_header("content-type", "application/json")
           |> post(
             "/api/agents/v1/pair",
             Jason.encode!(%{code: issued.code, name: "Sol", harness: "hermes"})
           )
           |> response(201)

    %{wallet: wallet, person: person}
  end

  test "an agent checks a name, claims it with its person's free claim, and the name is theirs",
       %{conn: conn, wallet: wallet} do
    insert_allowance(wallet, 1, 0)
    someone_else = "0x7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d7d"
    insert_allowance(someone_else, 1, 0)

    assert %{"problems" => [], "taken" => false, "claims" => %{"free" => 1, "paid" => 0}} =
             conn |> names("check", "agent-name") |> json_response(200)

    assert %{"claim" => claim} = conn |> names("claim", "agent-name") |> json_response(201)
    assert claim["ens_name"] == "agent-name.regent.eth"
    assert claim["owner_address"] == wallet
    assert used(wallet) == 1

    assert %{"taken" => true, "claims" => %{"free" => 0}} =
             conn |> names("check", "agent-name") |> json_response(200)

    assert used(someone_else) == 0
  end

  test "a refused claim records and spends nothing", %{conn: conn, wallet: wallet} do
    insert_allowance(wallet, 1, 0)

    insert_claim(7_100_001, "0x7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c", %{
      label: "held",
      fqdn: "held.agent.base.eth"
    })

    before = claim_count()

    assert %{"error" => %{"code" => "name_taken"}} =
             conn |> names("claim", "held") |> json_response(409)

    assert %{"error" => %{"code" => "name_breaks_rules"}} =
             conn |> names("claim", "-Bad") |> json_response(422)

    assert %{"problems" => [_ | _], "taken" => nil} =
             conn |> names("check", "-Bad") |> json_response(200)

    assert %{"problems" => [_ | _], "taken" => nil} =
             conn |> names("check", "line-end\n") |> json_response(200)

    assert %{"error" => %{"code" => "name_breaks_rules"}} =
             conn |> names("claim", "line-end\n") |> json_response(422)

    assert {claim_count(), used(wallet)} == {before, 0}

    assert conn |> names("claim", "spent-first") |> json_response(201)

    assert %{"error" => %{"code" => "no_free_claims"}} =
             conn |> names("claim", "spent-twice") |> json_response(409)

    assert {claim_count(), used(wallet)} == {before + 1, 1}
  end

  test "an unpaired agent can no longer claim for its person",
       %{conn: conn, wallet: wallet, person: person} do
    insert_allowance(wallet, 1, 0)
    [agent] = RegentAgents.list_my_agents!(actor: person)
    RegentAgents.unpair_agent!(agent, actor: person)

    assert %{"error" => %{"code" => "agent_not_paired"}} =
             conn |> names("claim", "not-mine") |> json_response(403)

    assert used(wallet) == 0
  end

  test "a request with anything but one name is refused", %{conn: conn} do
    for body <- [%{}, %{name: ""}, %{name: "ok-name", extra: 1}, %{name: 7}] do
      assert %{"error" => %{"code" => "invalid_input"}} =
               conn
               |> recycle()
               |> put_req_header("content-type", "application/json")
               |> post("/api/agent/v1/names/claim", Jason.encode!(body))
               |> json_response(400)
    end
  end

  defp names(conn, action, name) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post("/api/agent/v1/names/#{action}", Jason.encode!(%{name: name}))
  end

  defp used(address) do
    %{rows: [[used]]} =
      Repo.query!(
        "SELECT free_mints_used FROM regent_names.basenames_mint_allowances WHERE address = $1",
        [address]
      )

    used
  end

  defp claim_count do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM regent_names.basenames_mints")
    count
  end

  # The sign-in service verifies the request and names the key that signed it.
  defp siwa_verifies(wallet) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => wallet,
            "chain_id" => 8453,
            "audience" => "regents-test"
          },
          "agentRegistration" => nil,
          "agentBook" => nil
        }
      })
    end)
  end
end
