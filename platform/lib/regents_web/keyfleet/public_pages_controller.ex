defmodule RegentsWeb.Keyfleet.PublicPagesController do
  @moduledoc """
  Keyfleet's agent guides that are not the joining guide: `/keyfleet/llms.txt`,
  `/keyfleet/agents.md` and `/keyfleet/help`; no account or database reads. The
  reading pages themselves open in Keyfleet's frame
  (`RegentsWeb.Keyfleet.Components.Reading`).
  """
  use RegentsWeb, :controller
  alias RegentsWeb.Keyfleet.PublicDocuments

  def llms(conn, _params) do
    body = PublicDocuments.llms()
    conn |> cached(body) |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end

  def agents(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, PublicDocuments.agents())
  end

  def help(conn, _params) do
    body = PublicDocuments.help()
    conn |> cached(body) |> put_resp_content_type("text/markdown") |> send_resp(200, body)
  end

  # These documents change only with a release: a sha256 ETag of the body and a
  # five-minute public cache, as `RegentsWeb.Keyfleet.AgentFilesController` sends.
  defp cached(conn, body) do
    conn
    |> put_resp_header("etag", ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}"))
    |> put_resp_header("cache-control", "public, max-age=300")
  end
end
