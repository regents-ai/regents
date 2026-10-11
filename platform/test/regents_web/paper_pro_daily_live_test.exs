defmodule RegentsWeb.PaperProDailyLiveTest do
  use RegentsWeb.ConnCase, async: false

  alias Regents.Repo

  import Regents.PaperProDailyFixtures

  setup do
    # Sandbox-only fixture cleanup: this upload-only resource has no destroy action.
    Repo.delete_all("paper_pro_daily_papers")
    on_exit(&Regents.TestPublicationClock.reset/0)
    :ok
  end

  test "future content is absent from static HTML and the connected page", %{conn: conn} do
    today = paper_fixture!(Date.utc_today())
    future = paper_fixture!(Date.add(today.date, 1), %{title: "Unreleased secret title"})

    html = conn |> get("/paper-pro-daily") |> html_response(200)
    assert html =~ today.title
    refute html =~ future.title
    refute html =~ future.answer

    {:ok, view, html} = live(conn, "/paper-pro-daily")
    assert has_element?(view, "#papers-#{today.date}")
    refute has_element?(view, "#papers-#{future.date}")
    refute html =~ future.title
    refute html =~ future.answer
  end

  test "midnight refresh updates an open feed and resets pagination coherently", %{conn: conn} do
    before_midnight = ~U[2000-12-31 23:59:59.500000Z]
    today = DateTime.to_date(before_midnight)
    Regents.TestPublicationClock.freeze(before_midnight)
    older = Enum.map(1..7, &paper_fixture!(Date.add(today, -&1)))
    scheduled = paper_fixture!(Date.add(today, 1))
    future = paper_fixture!(Date.add(today, 2))
    {:ok, view, _html} = live(conn, "/paper-pro-daily")

    render_hook(view, "load_more", %{})
    assert has_element?(view, "#papers-#{List.last(older).date}")

    refute render(view) =~ scheduled.title
    before_picture = get(conn, "/paper-pro-daily/pictures/#{scheduled.date}?v=guessed")
    assert response(before_picture, 404) == "Not found"
    assert get_resp_header(before_picture, "cache-control") == ["no-store"]

    # Advance the test-build clock normally. The connected page's real OTP timer
    # must wake it; no handler message or host-clock change is used by the test.
    Regents.TestPublicationClock.advance(before_midnight)
    await_paper(view, scheduled.date, 100)

    assert has_element?(view, "#papers-#{scheduled.date}")
    assert has_element?(view, "#paper-daily-research-list a", scheduled.title)
    copy = view |> element("#paper-daily-copy-page") |> render()
    assert copy =~ scheduled.title
    assert copy =~ scheduled.arxiv_url
    refute copy =~ future.title

    assert response(get(conn, "/paper-pro-daily/pictures/#{scheduled.date}"), 200) ==
             scheduled.picture

    refute has_element?(view, "#papers-#{future.date}")
    assert has_element?(view, "#paper-daily-more[data-cursor='6']")

    render_hook(view, "load_more", %{})

    for paper <- [scheduled | older] do
      assert has_element?(view, "#papers-#{paper.date}")
    end

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_document(render(view)), "#paper-daily-list > li")
           ) ==
             8

    refute has_element?(view, "#paper-daily-more")
    refute render(view) =~ future.answer
  end

  test "a scroll before the timer resets yesterday's offset", %{conn: conn} do
    Regents.TestPublicationClock.freeze(~U[2000-12-31 12:00:00Z])
    older = Enum.map(0..6, &paper_fixture!(Date.add(~D[2000-12-31], -&1)))
    scheduled = paper_fixture!(~D[2001-01-01])
    {:ok, view, _html} = live(conn, "/paper-pro-daily")
    render_hook(view, "load_more", %{})

    Regents.TestPublicationClock.freeze(~U[2001-01-01 00:00:00Z])
    render_hook(view, "load_more", %{})
    assert has_element?(view, "#papers-#{scheduled.date}")
    assert has_element?(view, "#paper-daily-more[data-cursor='6']")
    render_hook(view, "load_more", %{})

    for paper <- [scheduled | older], do: assert(has_element?(view, "#papers-#{paper.date}"))
    refute has_element?(view, "#paper-daily-more")
  end

  test "a feed containing only scheduled papers remains empty", %{conn: conn} do
    future = paper_fixture!(Date.add(Date.utc_today(), 1))
    {:ok, view, html} = live(conn, "/paper-pro-daily")

    refute has_element?(view, "#paper-daily-list > li")
    refute has_element?(view, "#paper-daily-more")
    refute html =~ future.title
    refute html =~ future.answer
  end

  test "direct scheduled picture URLs return non-cacheable 404 responses", %{conn: conn} do
    current = paper_fixture!(Date.utc_today())
    future = paper_fixture!(Date.add(current.date, 1))

    for suffix <- ["", "?v=guessed"] do
      response = get(conn, "/paper-pro-daily/pictures/#{future.date}#{suffix}")
      assert response(response, 404) == "Not found"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end

    response = get(conn, "/paper-pro-daily/pictures/#{current.date}")
    assert response(response, 200) == current.picture
    assert get_resp_header(response, "content-type") == ["image/png"]
  end

  defp await_paper(view, date, remaining) when remaining > 0 do
    if has_element?(view, "#papers-#{date}") do
      :ok
    else
      Process.sleep(25)
      await_paper(view, date, remaining - 1)
    end
  end

  defp await_paper(view, date, 0), do: assert(has_element?(view, "#papers-#{date}"))
end
