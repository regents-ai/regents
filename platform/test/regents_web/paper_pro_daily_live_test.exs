defmodule RegentsWeb.PaperProDailyLiveTest do
  use RegentsWeb.ConnCase, async: false

  import ExUnit.CaptureIO
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

  @tag :tmp_dir
  test "put-paper saves inside the running site and the page shows the paper at once",
       %{conn: conn, tmp_dir: tmp_dir} do
    today = Date.utc_today()
    paper_fixture!(today)
    get(conn, "/paper-pro-daily")

    files = Path.join(tmp_dir, "a paper's files")
    File.mkdir_p!(files)
    File.write!(Path.join(files, "cover.png"), picture())

    File.write!(Path.join(files, "#{today}.md"), """
    ---
    title: Two Files Paper
    arxiv_url: https://arxiv.org/abs/2610.04075
    chatgpt_url: https://chatgpt.com/share/put-paper-two-files
    author: Test author
    picture_alt: Cover
    tags: [Swarms]
    ---
    Two files answer.
    """)

    assert release_command(tmp_dir, "put-paper", files, ["#{today}.md", "cover.png"]) =~
             ~s("Two Files Paper" saved.)

    assert conn |> get("/paper-pro-daily") |> html_response(200) =~ "Two Files Paper"

    File.write!(Path.join(files, "paper.md"), """
    ---
    title: Folder Paper
    date: #{Calendar.strftime(today, "%m-%d-%Y")}
    paper_url: https://arxiv.org/abs/2610.04076
    chatgpt_url: https://chatgpt.com/share/put-paper-folder
    chatgpt_model: Test author
    tags: [Memory, Safety]
    ---
    Folder answer.
    """)

    assert release_command(tmp_dir, "put-paper", tmp_dir, ["a paper's files"]) =~
             ~s("Folder Paper" saved.)

    assert conn |> get("/paper-pro-daily") |> html_response(200) =~ "Folder Paper"
  end

  @tag :tmp_dir
  test "tag-papers files papers inside the running site and the page shows them at once",
       %{conn: conn, tmp_dir: tmp_dir} do
    paper = paper_fixture!(Date.utc_today(), %{title: "Retagged paper", tags: ["Swarms"]})
    refute conn |> get("/paper-pro-daily?tags=Economics") |> html_response(200) =~ paper.title

    File.write!(Path.join(tmp_dir, "tags.yaml"), "#{paper.id}: [Economics, Science]\n")

    assert release_command(tmp_dir, "tag-papers", tmp_dir, ["tags.yaml"]) =~
             "Paper Pro Daily: 1 tagged."

    assert conn |> get("/paper-pro-daily?tags=Economics") |> html_response(200) =~ paper.title
    assert conn |> get("/paper-pro-daily.md?tags=Science") |> response(200) =~ paper.title
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

  test "choosing tags narrows the list, keeps the choice in the address and copies only those papers",
       %{conn: conn} do
    today = Date.utc_today()
    swarm = paper_fixture!(today, %{title: "Swarm paper", tags: ["Swarms"]})
    safety = paper_fixture!(Date.add(today, -1), %{title: "Safety paper", tags: ["Safety"]})
    both = paper_fixture!(Date.add(today, -2), %{title: "Both paper", tags: ["Safety", "Memory"]})
    paper_fixture!(Date.add(today, -3), %{title: "Memory only", tags: ["Memory"]})
    {:ok, view, _html} = live(conn, "/paper-pro-daily")

    assert has_element?(view, ".paper-daily__filtered--off[inert] #paper-daily-copy-filtered")

    view |> element("#paper-daily-tag-safety") |> render_click()
    assert_patch(view, "/paper-pro-daily?tags=Safety")
    assert has_element?(view, "#paper-daily-tag-safety[aria-pressed='true']")
    assert has_element?(view, "#days-#{safety.date}")
    assert has_element?(view, "#days-#{both.date}")
    refute has_element?(view, "#days-#{swarm.date}")
    refute has_element?(view, "#paper-daily-research-list", swarm.title)

    copied = filtered_markdown(conn, view)
    assert copied =~ "# Paper Pro Daily: Safety"
    assert copied =~ "## Safety paper"
    assert copied =~ "Tags: Safety, Memory"
    refute copied =~ swarm.title

    # A second tag adds its papers, and a paper opened from the list keeps the choice.
    view |> element("#paper-daily-tag-swarms") |> render_click()
    assert_patch(view, "/paper-pro-daily?tags=Swarms%2CSafety")
    assert filtered_markdown(conn, view) =~ swarm.title
    anchor = String.slice(safety.id, 0, 8)
    view |> element("#paper-daily-research-list a", safety.title) |> render_click()
    assert_patch(view, "/paper-pro-daily/#{anchor}?tags=Swarms%2CSafety")
    assert has_element?(view, "#paper-daily-tag-safety[aria-pressed='true']")
    refute has_element?(view, "#paper-daily-research-list", "Memory only")

    view |> element("#paper-daily-tag-swarms") |> render_click()
    view |> element("#paper-daily-tag-safety") |> render_click()
    assert_patch(view, "/paper-pro-daily")
    assert has_element?(view, "#days-#{swarm.date}")
    assert has_element?(view, ".paper-daily__filtered--off[inert]")
  end

  test "a shared address opens with its tags chosen and leaves out unknown ones", %{conn: conn} do
    today = Date.utc_today()
    memory = paper_fixture!(today, %{tags: ["Memory"]})
    swarm = paper_fixture!(Date.add(today, -1), %{tags: ["Swarms"]})

    {:ok, view, _html} = live(conn, "/paper-pro-daily?tags=Memory,Gossip")
    assert has_element?(view, "#paper-daily-tag-memory[aria-pressed='true']")
    assert has_element?(view, "#days-#{memory.date}")
    refute has_element?(view, "#days-#{swarm.date}")

    {:ok, view, _html} = live(conn, "/paper-pro-daily?tags=Economics")
    assert render(view) =~ "No papers with these tags."
    refute has_element?(view, "#paper-daily-list > li")

    # A paper outside the chosen tags opens the filtered list where it is.
    anchor = String.slice(swarm.id, 0, 8)
    {:ok, view, _html} = live(conn, "/paper-pro-daily/#{anchor}?tags=Memory")
    assert has_element?(view, "#days-#{memory.date}")
    refute has_element?(view, "#days-#{swarm.date}")
  end

  # What a press copies: the Markdown at the button's address.
  defp filtered_markdown(conn, view) do
    [url] =
      view
      |> element("#paper-daily-copy-filtered")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("data-copy-url")

    conn |> recycle() |> get(url) |> response(200)
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

  # Runs the shipped command with a stand-in for `bin/regents` that records its
  # arguments, then evaluates the recorded call here, from another folder, as the
  # running site would.
  # Runs a release command with a stand-in for the site, then makes the call it
  # sends inside the running site.
  defp release_command(tmp_dir, name, folder, arguments) do
    bin = Path.join(tmp_dir, "bin")
    command = Path.join(bin, name)
    stand_in = Path.join(bin, "regents")

    File.mkdir_p!(bin)
    File.cp!(Path.expand("../../rel/overlays/bin/#{name}", __DIR__), command)

    File.write!(stand_in, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$(dirname "$0")/called"
    """)

    File.chmod!(stand_in, 0o755)

    assert {_, 0} = System.cmd(command, arguments, cd: folder)

    assert ["rpc", call] =
             bin |> Path.join("called") |> File.read!() |> String.split("\n", trim: true)

    capture_io(fn -> Code.eval_string(call) end)
  end
end
