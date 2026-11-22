defmodule RegentsWeb.Patchbay.Forum.ToolHistory do
  @moduledoc """
  A page of a tool's versions, newest first (`Regents.Patchbay.Forum.Tool`'s
  `:history`), and the continuation handed out for the page after it.

  The continuation is signed for its site and tool, so a reader can only
  continue from a place Patchbay handed out, and it never expires. One more
  version than the page shows is read, so each version on the page can be
  set beside the one before it.
  """

  alias Regents.Patchbay.Forum
  alias RegentsWeb.Endpoint

  @salt "tool-history-v1"
  @max_bytes 4096

  @doc """
  `limit` versions of the tool named `name` on `site` from `cursor`, each
  loaded with `load`: the versions, the same with the one before the last
  (`comparison_versions`), and whether more follow with the continuation that
  reads them.
  """
  @spec page(Forum.Site.t(), String.t(), String.t() | nil, pos_integer(), list()) ::
          {:ok, map()} | {:error, :invalid_cursor} | {:error, term()}
  def page(site, name, cursor, limit, load) do
    with {:ok, opts} <- cursor_options(cursor, site.id, name),
         {:ok, page} <-
           Forum.tool_history(site.id, name,
             page: Keyword.put(opts, :limit, limit + 1),
             load: load
           ) do
      versions = Enum.take(page.results, limit)
      more? = length(page.results) > limit

      next =
        if more?,
          do:
            Phoenix.Token.sign(
              Endpoint,
              @salt,
              {site.id, name, List.last(versions).__metadata__.keyset}
            )

      {:ok,
       %{
         versions: versions,
         comparison_versions: page.results,
         pagination: %{has_more: more?, next_cursor: next}
       }}
    end
  end

  defp cursor_options(nil, _site_id, _name), do: {:ok, []}

  defp cursor_options(cursor, site_id, name)
       when is_binary(cursor) and byte_size(cursor) <= @max_bytes do
    case Phoenix.Token.verify(Endpoint, @salt, cursor, max_age: :infinity) do
      {:ok, {^site_id, ^name, keyset}} when is_binary(keyset) -> {:ok, [after: keyset]}
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp cursor_options(_cursor, _site_id, _name), do: {:error, :invalid_cursor}
end
