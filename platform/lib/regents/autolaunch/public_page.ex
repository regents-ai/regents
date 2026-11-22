defmodule Regents.Autolaunch.PublicPage do
  @moduledoc false
  @salt "public-listings-v1"

  def options(nil, _scope, limit), do: {:ok, [limit: limit]}

  def options(cursor, scope, limit) when is_binary(cursor) and byte_size(cursor) <= 4096 do
    case Phoenix.Token.verify(key_base(), @salt, cursor, max_age: 86_400) do
      {:ok, {^scope, keyset}} when is_binary(keyset) -> {:ok, [limit: limit, after: keyset]}
      _ -> {:error, :invalid_query}
    end
  end

  def options(_, _, _), do: {:error, :invalid_query}

  def metadata(page, scope) do
    cursor =
      if page.more? do
        Phoenix.Token.sign(
          key_base(),
          @salt,
          {scope, List.last(page.results).__metadata__.keyset}
        )
      end

    %{has_more: page.more?, next_cursor: cursor}
  end

  # The key the site's endpoint signs with, read from its setting: the core
  # does not call the web side.
  defp key_base,
    do:
      :regents |> Application.fetch_env!(RegentsWeb.Endpoint) |> Keyword.fetch!(:secret_key_base)
end
