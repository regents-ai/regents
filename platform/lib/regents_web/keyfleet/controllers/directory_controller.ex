defmodule RegentsWeb.Keyfleet.DirectoryController do
  @moduledoc """
  The open fleet directory, for anyone to compare the fleets without signing
  in: `/fleets.md` and `/fleets/<id>.md` as Markdown, `/api/v1/fleets` and
  `/api/v1/fleets/<id>` as JSON, all read from `Regents.Keyfleet.Directory`.

  Answers may be kept for 30 seconds; nothing is kept on the server. When
  anything the directory gives can't be read, it answers 503 and says so.

  A browser that opens `/fleets/<id>` or `/fleets/<id>/rooms` is sent to the
  fleet's page or its Public room, open in the fleet's hall; any other request there is sent to the
  fleet's Markdown. An unknown fleet is the site's not-found page, in HTML for a
  browser and in Markdown, pointing to `/fleets.md`, for anything else.
  """
  use RegentsWeb, :controller

  alias Regents.Keyfleet.{Directory, Fleets}
  alias RegentsWeb.ErrorHTML
  alias RegentsWeb.Keyfleet.{AgentReply, DirectoryMD, PageRead}
  alias RegentsWeb.Keyfleet.AgentTools.Public.Answer

  @unavailable "The fleet directory can't be read right now. Try again in a moment."

  def index_md(conn, _params) do
    case read(&Directory.list/0) do
      {:ok, fleets} -> markdown(conn, DirectoryMD.index(%{fleets: fleets, generated_at: now()}))
      {:error, _failure} -> unavailable_md(conn)
    end
  end

  # A fleet's Markdown sits at its id with `.md` after it; its id alone opens
  # the fleet.
  def show_md(conn, %{"file" => file}) do
    case String.split(file, ".md", parts: 2) do
      [fleet_id, ""] -> fleet_md(conn, fleet_id)
      _fleet_id -> open_fleet(conn, file, "")
    end
  end

  def rooms(conn, %{"fleet_id" => fleet_id}),
    do: open_fleet(conn, fleet_id, "?room=general")

  defp fleet_md(conn, fleet_id) do
    case read(fn -> Directory.fleet(fleet_id) end) do
      {:ok, fleet} -> markdown(conn, DirectoryMD.show(%{fleet: fleet, generated_at: now()}))
      :unknown -> not_found(conn, "md")
      {:error, _failure} -> unavailable_md(conn)
    end
  end

  # The JSON answers are the Claude connector's `fleets_list` and
  # `fleets_show` (`RegentsWeb.Keyfleet.AgentTools.Public.Answer`); only an answer
  # read whole is kept.
  def index_json(conn, params), do: json_answer(conn, Answer.answer(:fleets, params, nil, nil))
  def show_json(conn, params), do: json_answer(conn, Answer.answer(:fleet, params, nil, nil))

  defp json_answer(conn, {200, _body, _retry_after} = answer),
    do: conn |> cached() |> AgentReply.answer(answer)

  defp json_answer(conn, answer), do: AgentReply.answer(conn, answer)

  # A request that prefers HTML to Markdown; one asking for anything, as most
  # programs do, prefers Markdown here.
  defp browser?(conn) do
    conn
    |> get_req_header("accept")
    |> RegentAgentAccess.negotiate([{"md", "text", "markdown"}, {"html", "text", "html"}]) ==
      "html"
  end

  # A browser opens the fleet's page, or the page `under` it; anything else, an
  # agent, reads the fleet's Markdown.
  defp open_fleet(conn, fleet_id, under) do
    case {fleet_id in Fleets.catalog_ids(), browser?(conn)} do
      {true, true} -> redirect(conn, to: Fleets.path(fleet_id) <> under)
      {true, false} -> redirect(conn, to: ~p"/keyfleet/fleets/#{fleet_id <> ".md"}")
      {false, true} -> not_found(conn, "html")
      {false, false} -> not_found(conn, "md")
    end
  end

  defp not_found(conn, "md") do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(404, "# Not found\n\nNo fleet with that id. See `/keyfleet/fleets.md`.\n")
  end

  defp not_found(conn, format) do
    conn
    |> put_status(404)
    |> put_format(format)
    |> put_view(html: ErrorHTML)
    |> render(:"404")
  end

  # A read that fails outright is unavailable too, like a count that can't be
  # read.
  defp read(directory),
    do: with({:ok, answer} <- PageRead.run("directory", directory), do: answer)

  defp unavailable_md(conn) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(503, @unavailable <> "\n")
  end

  defp markdown(conn, body) do
    conn
    |> cached()
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, body)
  end

  defp cached(conn), do: put_resp_header(conn, "cache-control", "public, max-age=30")

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
