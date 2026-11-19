defmodule RegentAgentAccess do
  @moduledoc """
  Content negotiation for pages that are published to people and to agents at
  the same address.

  The functions here are pure. `RegentAgentAccess.Plug` applies them to a
  connection, and `RegentAgentAccess.Recovery` formats the error bodies. The
  product keeps its own list of public documents, its routes and its policies.
  """

  @typedoc ~S|A servable format: its Phoenix format name, media type and subtype, e.g. `{"md", "text", "markdown"}`.|
  @type format :: {name :: String.t(), type :: String.t(), subtype :: String.t()}

  @doc """
  Picks the format the `accept` header values prefer, or `nil` when every
  offered format is refused.

  Quality wins first, then the more specific media range, then the order of
  `formats`. A specific `q=0` exclusion overrides a wildcard, which Phoenix's
  browser-oriented `accepts/2` does not distinguish. No header means `*/*`.
  """
  @spec negotiate([String.t()], [format()]) :: String.t() | nil
  def negotiate(accept, formats) do
    ranges = accept |> default_accept() |> Enum.flat_map(&ranges/1)

    formats
    |> Enum.with_index()
    |> Enum.map(fn {{format, type, subtype}, order} ->
      {specificity, quality} =
        ranges
        |> Enum.flat_map(fn
          {^type, ^subtype, q} -> [{2, q}]
          {^type, "*", q} -> [{1, q}]
          {"*", "*", q} -> [{0, q}]
          _ -> []
        end)
        |> Enum.max(fn -> {-1, 0.0} end)

      {quality, specificity, -order, format}
    end)
    |> Enum.filter(fn {quality, _, _, _} -> quality > 0 end)
    |> Enum.max(fn -> nil end)
    |> case do
      nil -> nil
      {_, _, _, format} -> format
    end
  end

  @doc """
  Adds `Accept` to the `vary` header values already on a response, keeping every
  other dimension and collapsing to `*` when one of them is `*`.
  """
  @spec merge_vary([String.t()]) :: String.t()
  def merge_vary(values) do
    values =
      values
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Kernel.++(["Accept"])
      |> Enum.uniq_by(&String.downcase/1)

    if "*" in values, do: "*", else: Enum.join(values, ", ")
  end

  defp default_accept([]), do: ["*/*"]
  defp default_accept(accept), do: accept

  defp ranges(header) do
    header
    |> String.split(",")
    |> Enum.flat_map(fn value ->
      case Plug.Conn.Utils.media_type(value) do
        {:ok, type, subtype, params} -> [{type, subtype, quality(params)}]
        :error -> []
      end
    end)
  end

  defp quality(params) do
    case Float.parse(Map.get(params, "q", "1")) do
      {q, ""} when q >= 0 and q <= 1 -> q
      _ -> 0.0
    end
  end
end
