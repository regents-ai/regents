defmodule Regents.Keyfleet.Code.ReceivePack do
  @moduledoc """
  Which branches and tags one push moved, read from git's own exchange: the
  commands at the start of the request (`old new ref`, after any `shallow`
  lines, the first carrying the client's capabilities) and the store's report
  of each (`ok ref` or `ng ref reason`), inside side band 1 when the client
  asked for side bands.

  Only a ref the store reported `ok` and that still points at a commit counts:
  a deleted branch moved nothing anyone can read.
  """

  @doc "The refs `request` moved that `response` reports done, each `%{ref:, head:}`."
  def updates(request, response) do
    with {:ok, lines} <- lines(request),
         [first | rest] <- Enum.drop_while(lines, &String.starts_with?(&1, "shallow ")),
         [command | caps] = String.split(first, <<0>>, parts: 2),
         caps = caps |> Enum.join() |> String.split(),
         true <- "report-status" in caps or "report-status-v2" in caps,
         {:ok, report} <- report(response, caps) do
      done = for "ok " <> ref <- report, into: MapSet.new(), do: String.trim_trailing(ref)

      for line <- [command | rest],
          [_old, new, ref] <- [String.split(String.trim_trailing(line), " ")],
          ref in done and not deletion?(new),
          do: %{ref: ref, head: new}
    else
      _unreadable -> []
    end
  end

  defp report(response, caps) do
    if "side-band-64k" in caps or "side-band" in caps do
      with {:ok, packets} <- lines(response) do
        packets
        |> Enum.flat_map(fn
          <<1, data::binary>> -> [data]
          _progress -> []
        end)
        |> Enum.join()
        |> lines()
      end
    else
      lines(response)
    end
  end

  defp deletion?(head), do: head =~ ~r/\A0+\z/

  # The packet lines up to the first flush packet, or `:error` when they
  # don't reach one.
  defp lines(data, acc \\ [])

  defp lines("0000" <> _rest, acc), do: {:ok, Enum.reverse(acc)}

  defp lines(<<size::binary-size(4), rest::binary>>, acc) do
    with {length, ""} when length > 4 <- Integer.parse(size, 16),
         <<line::binary-size(^length - 4), rest::binary>> <- rest do
      lines(rest, [line | acc])
    else
      _broken -> :error
    end
  end

  defp lines(_data, _acc), do: :error
end
