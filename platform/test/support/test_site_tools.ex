defmodule Regents.TestSiteTools do
  @moduledoc """
  Answers each Regent site's published tool list in tests and on the browser
  test server, so the lists of every site's tools never depend on the live
  sites. Each site lists three tools, for every page, its home page and one
  other page.
  """

  @behaviour Plug

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    Req.Test.json(conn, %{"tools" => tools(conn.host)})
  end

  defp tools(host) do
    [
      tool(host, "browse", "site"),
      tool(host, "search", "/"),
      tool(host, "post", "/forum")
    ]
  end

  defp tool(host, verb, scope) do
    %{
      "name" => "#{verb}_#{String.replace(host, ".", "_")}",
      "title" => "#{String.capitalize(verb)} #{host}",
      "description" => "The #{verb} tool #{host} offers agents.",
      "scope" => scope
    }
  end
end
