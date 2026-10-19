defmodule RegentsWeb.PublicReadsTest do
  use RegentsWeb.ConnCase, async: false

  alias Regents.{Accounts, Blog, Formation}
  alias Regents.Actors.{Human, System}

  import Regents.PaperProDailyFixtures

  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO/aF1cAAAAASUVORK5CYII="
       )

  # The agent reads show exactly what the pages show: a future paper, a draft
  # Article and a future-dated Article are absent from the lists and their
  # detail reads, and published records come back whole.
  test "papers and Articles that are not public yet stay hidden", %{conn: conn} do
    today = Date.utc_today()
    published = paper_fixture!(today)
    future = paper_fixture!(Date.add(today, 1))

    papers = conn |> get("/api/v1/reading/papers") |> json_response(200)
    assert Enum.map(papers["papers"], & &1["id"]) == [published.id]

    assert build_conn()
           |> get("/api/v1/reading/papers/#{published.id}")
           |> json_response(200)
           |> get_in(["paper", "analysis_markdown"]) == published.answer

    assert build_conn() |> get("/api/v1/reading/papers/#{future.id}") |> json_response(404)

    article!("published-article", today, false)
    article!("draft-article", today, true)
    article!("future-article", Date.add(today, 1), false)

    articles = build_conn() |> get("/api/v1/reading/articles") |> json_response(200)
    assert Enum.map(articles["articles"], & &1["slug"]) == ["published-article"]

    assert build_conn()
           |> get("/api/v1/reading/articles/published-article")
           |> json_response(200)
           |> get_in(["article", "markdown"]) == "Published text."

    for slug <- ["draft-article", "future-article"] do
      assert build_conn() |> get("/api/v1/reading/articles/#{slug}") |> json_response(404)
    end
  end

  # The profile read returns the five public fields and nothing else.
  test "a public Regent profile returns only its public fields", %{conn: conn} do
    wallet = "0x5555555555555555555555555555555555555555"

    account =
      Accounts.register_verified!("did:privy:public-read", wallet, [wallet], actor: %System{})

    actor = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("reading-atlas", "Reading Atlas", actor: actor)
    Formation.update_profile!(regent, "Reading Atlas", "Public summary.", actor: actor)

    assert conn |> get("/api/v1/regents/reading-atlas") |> json_response(200) == %{
             "profile" => %{
               "slug" => "reading-atlas",
               "display_name" => "Reading Atlas",
               "summary" => "Public summary.",
               "avatar_url" => nil,
               "verified_wallet_address" => wallet
             }
           }
  end

  defp article!(slug, date, draft) do
    Blog.put_post!(
      %{
        slug: slug,
        title: slug,
        date: date,
        author: "Test author",
        author_x: "https://x.com/regents",
        authors: [%{name: "Test author", x: "regents"}],
        markdown: if(slug == "published-article", do: "Published text.", else: "Hidden text."),
        draft: draft,
        cover: @png,
        cover_alt: "Cover for #{slug}"
      },
      actor: %System{}
    )
  end
end
