defmodule RegentsWeb.PaperProDailyLiveTest do
  use RegentsWeb.ConnCase, async: false

  import Regents.PaperProDailyFixtures

  alias RegentsWeb.PaperProDaily.Feed

  setup do
    Feed.delete_all!()
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
    assert has_element?(view, "#days-#{today.date}")
    refute has_element?(view, "#days-#{future.date}")
    refute html =~ future.title
    refute html =~ future.answer
  end

  test "midnight refresh updates an open feed and resets pagination coherently", %{conn: conn} do
    today = Date.utc_today()
    older = Enum.map(1..7, &paper_fixture!(Date.add(today, -&1)))
    future = paper_fixture!(Date.add(today, 1))
    {:ok, view, _html} = live(conn, "/paper-pro-daily")

    render_hook(view, "load_more", %{})
    assert has_element?(view, "#days-#{List.last(older).date}")

    # Exercise the timer handler without sleeping or changing the host clock.
    # The exact clock boundary is covered by PaperProDailyTest.
    current = paper_fixture!(today)
    # A real midnight starts a new day's readings.
    Feed.delete_all!()
    send(view.pid, :publication_midnight)

    assert has_element?(view, "#days-#{current.date}")
    refute has_element?(view, "#days-#{future.date}")
    assert has_element?(view, "#paper-daily-more[data-cursor='6']")

    render_hook(view, "load_more", %{})

    for paper <- [current | older] do
      assert has_element?(view, "#days-#{paper.date}")
    end

    refute has_element?(view, "#paper-daily-more")
    refute render(view) =~ future.answer
  end

  test "one open reads only what it shows, and a crowd of opens shares it", %{conn: conn} do
    today = Date.utc_today()
    shown = paper_fixture!(today)
    Enum.each(1..5, &paper_fixture!(Date.add(today, -&1)))

    later =
      paper_fixture!(Date.add(today, -6), %{answer: "An answer from further down the page."})

    Feed.delete_all!()

    papers_reads = count_papers_reads()

    {:ok, _view, html} = live(conn, "/paper-pro-daily")
    assert html =~ shown.title
    refute html =~ later.answer
    assert length(papers_reads.()) == 2

    refute conn |> get("/paper-pro-daily") |> html_response(200) =~ later.answer
    assert [outline, days] = papers_reads.()
    refute outline =~ "answer"
    assert days =~ "answer"
  end

  test "the whole page is one Markdown address, without scheduled papers", %{conn: conn} do
    today = Date.utc_today()

    older =
      paper_fixture!(Date.add(today, -6), %{answer: "An answer from further down the page."})

    future = paper_fixture!(Date.add(today, 1), %{title: "Unreleased secret title"})

    conn = get(conn, "/paper-pro-daily.md")

    assert response_content_type(conn, :markdown) =~ "text/markdown"
    assert conn.resp_body =~ older.answer
    refute conn.resp_body =~ future.title
  end

  test "each paper shares a link that opens it, even on a later day behind another paper", %{
    conn: conn
  } do
    today = Date.utc_today()
    Enum.each(0..6, &paper_fixture!(Date.add(today, -&1)))
    first = paper_fixture!(Date.add(today, -7))
    second = paper_fixture!(first.date, %{arxiv_url: "https://arxiv.org/abs/2610.04075"})
    anchor = String.slice(second.id, 0, 8)
    path = "/paper-pro-daily/#{anchor}"

    {:ok, view, _html} = live(conn, "/paper-pro-daily")
    refute has_element?(view, "#paper-#{second.id}-share")

    render_patch(view, path)
    assert_push_event(view, "paper-daily:go-to-paper", %{target: ^anchor})
    assert has_element?(view, ~s([id="#{anchor}"]))
    assert has_element?(view, "#paper-#{first.id}-share")

    assert has_element?(
             view,
             ~s(#paper-#{second.id}-share[data-copy-text="#{RegentsWeb.Endpoint.url()}#{path}"])
           )

    {:ok, opened, _html} = live(conn, path)
    assert_push_event(opened, "paper-daily:go-to-paper", %{target: ^anchor})
  end

  test "a shared paper's link describes only that paper", %{conn: conn} do
    paper =
      paper_fixture!(Date.utc_today(), %{
        title: "Proofs & <limits>",
        authors: ["A. Writer", "B. Reader", "C. Author", "D. Fourth"]
      })

    anchor = String.slice(paper.id, 0, 8)
    html = conn |> get("/paper-pro-daily/#{anchor}") |> html_response(200)
    head = html |> Floki.parse_document!() |> Floki.find("head")
    content = &(head |> Floki.find(~s(meta[property="#{&1}"])) |> Floki.attribute("content"))

    assert content.("og:title") == ["Proofs & <limits>"]

    assert content.("og:description") ==
             [
               "Daily Research Papers Reviewed by ChatGPT Pro · A. Writer, B. Reader, C. Author et al."
             ]

    build = Application.fetch_env!(:regents, :build).commit

    assert [image] = content.("og:image")
    assert image == "#{RegentsWeb.Endpoint.url()}/paper-pro-daily/#{anchor}/share.png?v=#{build}"

    card = get(conn, image)
    assert <<0x89, "PNG", _::binary>> = response(card, 200)
    {:ok, picture} = Vix.Vips.Image.new_from_buffer(card.resp_body)
    assert {Vix.Vips.Image.width(picture), Vix.Vips.Image.height(picture)} == {1200, 630}

    assert <<0x89, "PNG", _::binary>> =
             conn |> get("/paper-pro-daily/share.png") |> response(200)
  end

  test "a link to a scheduled or unknown paper finds nothing", %{conn: conn} do
    future = paper_fixture!(Date.add(Date.utc_today(), 1), %{title: "Unreleased secret title"})
    anchor = String.slice(future.id, 0, 8)

    for path <- [
          "/paper-pro-daily/#{anchor}",
          "/paper-pro-daily/00000000",
          "/paper-pro-daily/nope"
        ] do
      assert_error_sent(404, fn -> get(conn, path) end)
    end

    assert conn |> get("/paper-pro-daily/#{anchor}/share.png") |> response(404)
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
      response = get(conn, "/paper-pro-daily/pictures/#{future.id}#{suffix}")
      assert response(response, 404) == "Not found"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end

    response = get(conn, "/paper-pro-daily/pictures/#{current.id}")
    assert response(response, 200) == current.picture
    assert get_resp_header(response, "content-type") == ["image/png"]
  end

  # The queries that read the papers table from now on, whichever process ran them.
  defp count_papers_reads do
    {:ok, reads} = Agent.start_link(fn -> [] end)
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      [:regents, :repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if query =~ ~s("paper_pro_daily_papers"),
          do: Agent.update(reads, &[query | &1])
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    fn -> reads |> Agent.get(& &1) |> Enum.reverse() end
  end
end
