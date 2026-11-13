defmodule RegentsWeb.PointsPageTest do
  # What a signed-in person gets from Points on the first render, with no wait:
  # their own figures, the actions still open with where to do them, and their own
  # row on the leaderboard beside other people's names or wallets. Awards are earned the
  # way the site earns them: an account is made, and the queued checks are run. The
  # board every reader shares is then read once, as its producer reads it on notice.
  # Ported from ash-template's `AshTemplateWeb.PointsPageTest`.
  use RegentsWeb.ConnCase, async: false

  alias Regents.{Accounts, SharedProfiles, SharedReading}
  alias Regents.Actors.System
  alias Regents.Points.Board

  @wallet "0x" <> String.duplicate("b", 40)
  @other "0x" <> String.duplicate("9", 40)

  setup {Regents.EnsLookups, :await_at_exit}

  setup %{conn: conn} do
    previous =
      Map.new([:starts_at, :approved_rules], &{&1, Application.get_env(:regent_points, &1)})

    Application.put_env(:regent_points, :starts_at, DateTime.add(DateTime.utc_now(), -1, :day))
    Application.put_env(:regent_points, :approved_rules, ~w(account.activated social.x))
    Regents.RateLimiter.reset()

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:regent_points, key, value) end)
      SharedReading.delete(Board.key())
      Regents.RateLimiter.reset()
    end)

    other =
      Accounts.register_verified!("did:privy:points-page-other", @other, [@other],
        actor: %System{}
      )

    person =
      Accounts.register_verified!("did:privy:points-page", @wallet, [@wallet], actor: %System{})

    # The account's time is kept to the second, rounded, so it can be up to half a
    # second ahead; Points' check waits for it.
    Process.sleep(1_000)
    assert %{failure: 0} = Oban.drain_queue(queue: :points, with_recursion: true)
    assert :ok = Board.read()

    conn =
      conn
      |> put_req_header("accept", "text/html")
      |> init_test_session(%{human_account_id: person.id})

    %{conn: conn, other: other, person: person}
  end

  test "the first render carries the person's figures, open actions and place", %{conn: conn} do
    page = conn |> get("/account/points") |> html_response(200) |> LazyHTML.from_document()

    assert text(page, "#points-total .rg-points-total__figure") == "25"
    assert text(page, "#points-total dl") =~ "+25"
    assert text(page, "#points-total dl") =~ "#1"

    # The account's own award is ticked; the social link is open and says where to go.
    assert text(page, ~s(#points-todo li[data-done="true"])) =~ "Account activated"

    assert LazyHTML.attribute(
             LazyHTML.query(page, ~s(#points-todo li[data-done="false"] a)),
             "href"
           ) ==
             ["/account/connections"]

    # Two accounts level on points share first place; only the reader's row is marked.
    # Other tests' awards commit on purpose and sit below them.
    ranks =
      page
      |> LazyHTML.query("#points-board li .rg-points-board__rank")
      |> Enum.map(&LazyHTML.text/1)

    assert Enum.take(ranks, 2) == ["1", "1"]
    assert Enum.count(ranks, &(&1 == "1")) == 2
    assert page |> LazyHTML.query(~s(#points-board li[data-you="true"])) |> Enum.count() == 1
    refute text(page, "#points-page") =~ "Loading"
  end

  # The board shows the names people saved in their shared profiles. Names are not
  # unique, and everyone who has only the first award is level on points: two people
  # named alike at one place still get a picture each.
  test "two people with one name, level on points, each keep their own picture", %{
    conn: conn,
    other: other,
    person: person
  } do
    SharedProfiles.put_name!(person.privy_user_id, "Sam")
    SharedProfiles.put_name!(other.privy_user_id, "Sam")

    assert :ok = Board.read()
    page = conn |> get("/account/points") |> html_response(200) |> LazyHTML.from_document()

    faces =
      for row <- LazyHTML.query(page, "#points-board li"),
          LazyHTML.text(row) =~ "Sam",
          id <- row |> LazyHTML.query("[id]") |> LazyHTML.attribute("id"),
          do: id

    assert text(page, "#points-board") |> String.split("Sam") |> length() == 3
    assert length(faces) == 2
    assert faces == Enum.uniq(faces)
  end

  # Every wallet is public: another person with no name shows by their wallet, whose
  # copy icon copies it in full. Nothing else about the account leaves it.
  test "a person with no name shows by their wallet, with its copy icon", %{
    conn: conn,
    other: other
  } do
    html = conn |> get("/account/points") |> html_response(200)
    page = LazyHTML.from_document(html)

    copies =
      page
      |> LazyHTML.query(
        ~s(#points-board li[data-you="false"] [id^="points-board-wallet-"][id$="-copy"])
      )
      |> LazyHTML.attribute("data-copy-text")

    assert @other in copies
    assert text(page, "#points-board") =~ Regent.Primitives.short_address(@other)
    refute html =~ other.privy_user_id
  end

  # A person's paired agent reads the same figures the page shows, and its copy of
  # the leaderboard carries a place, a name or wallet and a total for each row.
  test "a paired agent is answered with the page's figures", %{conn: conn, person: person} do
    page = conn |> get("/account/points") |> html_response(200) |> LazyHTML.from_document()
    answer = agent_answer(person)

    assert answer["points"] == text(page, "#points-total .rg-points-total__figure")
    assert "#" <> to_string(answer["rank"]) == "#1"
    assert answer["earned_today"] == "25"

    assert %{"done" => true, "left" => false} =
             Enum.find(answer["to_do"], &(&1["label"] == "Account activated"))

    assert %{"done" => false, "left" => true} =
             Enum.find(answer["to_do"], &(&1["label"] == "X account linked"))

    assert length(answer["leaderboard"]) ==
             page |> LazyHTML.query("#points-board li") |> Enum.count()

    for row <- answer["leaderboard"] do
      assert row |> Map.keys() |> Enum.sort() == ~w(ens_name name points rank wallet you)
    end

    assert %{"name" => nil, "ens_name" => nil, "you" => false} =
             Enum.find(answer["leaderboard"], &(&1["wallet"] == @other))
  end

  # After the last season nothing earns: the page and the agent list no action to
  # do, and the account's figures stay.
  test "after the last season, no action is listed and the Bonus card has ended", %{
    conn: conn,
    person: person
  } do
    days = RegentPoints.Rules.season_count() * 30 + 1
    Application.put_env(:regent_points, :starts_at, DateTime.add(DateTime.utc_now(), -days, :day))

    page = conn |> get("/account/points") |> html_response(200) |> LazyHTML.from_document()
    answer = agent_answer(person)

    assert Enum.empty?(LazyHTML.query(page, "#points-todo li"))
    assert Enum.empty?(LazyHTML.query(page, "#points-todo .rg-points-todo__left"))
    assert answer["to_do"] == []
    assert answer["points"] == text(page, "#points-total .rg-points-total__figure")
    assert answer["points"] == "25"

    # The Bonus card is in the shared card's ended state, which reads apart from its
    # not-yet-open one, and marks no tier as held.
    refute bonus_line(:ended) == bonus_line(:closed)
    assert text(page, "#points-bonus .rg-points-bonus__held") == bonus_line(:ended)
    assert Enum.empty?(LazyHTML.query(page, ~s(#points-bonus li[data-held="true"])))
  end

  # While the board is held for signed-in readers, a signed-out visitor gets none of it.
  test "a signed-out visitor is asked to sign in and gets nothing from the board" do
    assert {:ok, %{reading: %{top: [_ | _] = top}}} = SharedReading.fetch(Board.key())

    html =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> get("/account/points")
      |> html_response(200)

    page = LazyHTML.from_document(html)

    assert Enum.count(LazyHTML.query(page, "#points-signed-out")) == 1
    assert Enum.empty?(LazyHTML.query(page, "#points-total"))
    assert Enum.empty?(LazyHTML.query(page, "#points-board"))
    for row <- top, shown <- [row.name, row.wallet], shown, do: refute(html =~ shown)
  end

  # Where the page would show the board as not read, the agent gets no half answer.
  test "while the board is not read, the agent's whole answer is unavailable", %{person: person} do
    SharedReading.delete(Board.key())

    assert %{"error" => %{"code" => "unavailable"}} =
             person |> agent_points() |> json_response(503)
  end

  defp agent_answer(person), do: person |> agent_points() |> json_response(200)

  # Pairs an agent with the person and asks for Points as that agent; the sign-in
  # service's check of the agent's signature is answered here.
  defp agent_points(person) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      Req.Test.json(conn, %{
        code: "http_envelope_valid",
        data: %{
          verified: true,
          agentBook: nil,
          agentRegistration: nil,
          principal: %{
            kind: "wallet",
            wallet_address: @wallet,
            chain_id: 8453,
            audience: "regents-test"
          }
        }
      })
    end)

    code =
      RegentAgents.issue_pairing_code!(
        actor: %RegentAgents.Person{privy_user_id: person.privy_user_id}
      )

    RegentAgents.pair_agent!(code.code, "Fixture", :codex,
      actor: %RegentAgents.Agent{wallet: @wallet}
    )

    build_conn()
    |> put_req_header("x-siwa-signature", "fixture-proof")
    |> get("/api/v1/account/points")
  end

  defp bonus_line(state) do
    assigns = [id: "bonus", state: state, tiers: [], periods: [], tip: []]

    render_component(&Regent.Points.bonus/1, assigns)
    |> LazyHTML.from_fragment()
    |> text(".rg-points-bonus__held")
  end

  defp text(page, selector),
    do: page |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()
end
