defmodule RegentsWeb.ReadingController do
  @moduledoc "Public Reading records, through the same publication policies as their pages."
  use RegentsWeb, :controller

  alias Regents.{Blog, PaperProDaily}
  alias RegentsWeb.{Literature, PublicDocuments}

  def papers(conn, params),
    do: collection(conn, params, :papers, &PaperProDaily.paper_feed/1, &paper_summary/1)

  def articles(conn, params),
    do: collection(conn, params, :articles, &Blog.post_feed/1, &article_summary/1)

  def paper(conn, %{"id" => id}) do
    with :ok <- no_query(conn),
         {:ok, paper} <- PaperProDaily.get_paper(id) do
      if paper,
        do: json(conn, %{paper: Map.put(paper_summary(paper), :analysis_markdown, paper.answer)}),
        else:
          refuse(
            conn,
            404,
            "not_found",
            "That paper is not available.",
            "List published papers first."
          )
    else
      :error -> invalid_query(conn)
      {:error, %Ash.Error.Invalid{}} -> invalid_id(conn)
      {:error, _} -> unavailable(conn)
    end
  end

  def article(conn, %{"slug" => slug}) do
    with :ok <- no_query(conn),
         true <- byte_size(slug) in 1..63 and Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, slug),
         {:ok, article} <- Blog.get_post(slug) do
      if article,
        do:
          json(conn, %{article: Map.put(article_summary(article), :markdown, article.markdown)}),
        else:
          refuse(
            conn,
            404,
            "not_found",
            "That article is not available.",
            "List published articles first."
          )
    else
      :error -> invalid_query(conn)
      false -> invalid_id(conn)
      {:error, _} -> unavailable(conn)
    end
  end

  def literature(conn, params) when map_size(params) == 0 do
    books =
      Enum.map(
        Literature.books(),
        &Map.put(&1, :cover_url, PublicDocuments.url("/images/literature/#{&1.slug}.webp"))
      )

    json(conn, %{
      books: books,
      scores: %{
        minimum: -10,
        maximum: 10,
        meaning:
          "Editorial readings of each book's themes, not measurements or claims about the author's beliefs."
      }
    })
  end

  def literature(conn, _params), do: invalid_query(conn)

  defp collection(conn, params, key, read, present) do
    with {:ok, page} <- pagination(params),
         {:ok, result} <- read.(page: page) do
      json(conn, %{
        key => Enum.map(result.results, present),
        :pagination => %{
          has_more: result.more?,
          next_cursor:
            if(result.more?, do: List.last(result.results).__metadata__.keyset, else: nil)
        }
      })
    else
      :error ->
        invalid_query(conn)

      {:error, %Ash.Error.Invalid{}} ->
        refuse(
          conn,
          400,
          "invalid_cursor",
          "That cursor is not valid.",
          "Start without after, then use pagination.next_cursor unchanged."
        )

      {:error, _} ->
        unavailable(conn)
    end
  end

  defp pagination(params) when map_size(params) == 0, do: {:ok, []}

  defp pagination(%{"after" => cursor} = params)
       when map_size(params) == 1 and is_binary(cursor) and byte_size(cursor) in 1..2048,
       do: {:ok, [after: cursor]}

  defp pagination(_params), do: :error

  defp no_query(%{query_params: params}) when map_size(params) == 0, do: :ok
  defp no_query(_conn), do: :error

  defp paper_summary(paper) do
    %{
      id: paper.id,
      title: paper.title,
      date: paper.date,
      authors: paper.authors,
      paper_url: paper.arxiv_url,
      chatgpt_url: paper.chatgpt_url,
      chatgpt_model: paper.author,
      cover_url:
        PublicDocuments.url(
          "/paper-pro-daily/pictures/#{paper.id}?v=#{DateTime.to_unix(paper.updated_at, :microsecond)}"
        ),
      cover_alt: paper.picture_alt,
      url: PublicDocuments.url("/paper-pro-daily#paper-#{paper.id}-title")
    }
  end

  defp article_summary(article) do
    article
    |> Map.take([:slug, :title, :description, :date, :author, :author_x, :authors])
    |> Map.merge(%{
      url: PublicDocuments.url("/articles/#{article.slug}"),
      cover_url:
        PublicDocuments.url(
          "/articles/covers/#{article.slug}?v=#{DateTime.to_unix(article.updated_at, :microsecond)}"
        ),
      cover_alt: article.cover_alt
    })
  end

  defp invalid_query(conn),
    do:
      refuse(
        conn,
        400,
        "invalid_query",
        "This read accepts only its documented query fields.",
        "Lists accept an optional after cursor; detail and literature reads take no query parameters."
      )

  defp invalid_id(conn),
    do:
      refuse(
        conn,
        400,
        "invalid_id",
        "That record identifier is not valid.",
        "Use the id or slug from the list response."
      )

  defp unavailable(conn),
    do:
      refuse(
        conn,
        503,
        "unavailable",
        "The published records could not be read.",
        "Try again in a moment."
      )

  defp refuse(conn, status, code, message, hint),
    do: conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
end
