defmodule RegentsWeb.Keyfleet.FeedLines do
  @moduledoc """
  The lines of a fleet's hall feed, from a page of its activity
  (`Regents.Keyfleet.Activity`), newest first. Each item is a line of its own, except
  transfers: transfers next to each other in the feed that moved Keys to one
  wallet, each recorded within ten minutes of the one after it, are one
  `:moved` line, with `facts` `token_ids` (lowest first) and `to`, the wallet.

  A `:moved` line takes the id of its oldest transfer, so a transfer that joins
  it later finds it in place, and the time of its newest; `since` is the time of
  its oldest.

  Ten minutes from one transfer to the next: the chain is read every five
  minutes and every record one read takes shares its time, so a batch the
  chain spread over two reads is still one line, while a move made later, after
  a quiet stretch, is a line of its own. Each transfer is weighed against its
  neighbour alone, so two pages joined where they meet (`join/2`) read as one
  page would.

  Grouping is for the page alone: the activity agents read keeps each transfer.
  """

  @window 600

  @doc """
  `items`, a page of the fleet's activity, as lines; `receivers` names the
  wallet each transfer moved its Key to (`Regents.Keyfleet.Activity.receivers/2`).
  """
  def lines(items, receivers), do: items |> Enum.map(&line(&1, receivers)) |> runs()

  @doc """
  The lines of the next page down, `lines`, under `above`, the lowest line on
  show: `{:joined, lines}` when the first of them carries on its run of
  transfers, that line and `above` made one; `{:apart, lines}` otherwise.
  """
  def join(above, [first | rest] = lines) do
    if joins?(first, above), do: {:joined, [merge(above, first) | rest]}, else: {:apart, lines}
  end

  def join(_above, []), do: {:apart, []}

  @doc """
  A fresh first page's `lines`, drawn over the pages on show below it
  (`shown`, their ids). A run of transfers at its foot that isn't on show is
  the newer part of one on show below, whose older transfers have slipped off
  this page, so it is left as it is drawn there.
  """
  def over(lines, shown) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(&(&1.kind == :moved and not MapSet.member?(shown, &1.id)))
    |> Enum.reverse()
  end

  defp line(%{kind: :transfer} = item, receivers),
    do: %{
      id: item.id,
      at: item.at,
      since: item.at,
      kind: :moved,
      facts: %{token_ids: [item.facts.token_id], to: Map.fetch!(receivers, item.id)}
    }

  defp line(item, _receivers), do: item

  defp runs([newer, older | rest]) do
    if joins?(older, newer),
      do: runs([merge(newer, older) | rest]),
      else: [newer | runs([older | rest])]
  end

  defp runs(lines), do: lines

  # `older` sits just below `newer` in the feed: both moved Keys to one wallet,
  # the newer's first transfer within the window of the older's last.
  defp joins?(%{kind: :moved} = older, %{kind: :moved} = newer),
    do:
      older.facts.to == newer.facts.to and
        DateTime.diff(newer.since, older.at, :second) <= @window

  defp joins?(_older, _newer), do: false

  defp merge(newer, older),
    do: %{
      older
      | at: newer.at,
        facts: %{
          older.facts
          | token_ids: Enum.sort(Enum.uniq(older.facts.token_ids ++ newer.facts.token_ids))
        }
    }
end
