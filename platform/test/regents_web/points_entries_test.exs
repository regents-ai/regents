defmodule RegentsWeb.PointsEntriesTest do
  # A reader's place beside the shared board: their own row's when they are listed,
  # and their summary's, with their own total, when they sit below the ten.
  # Ported from ash-template's `AshTemplateWeb.PointsEntriesTest`.
  use ExUnit.Case, async: true

  alias RegentsWeb.PointsEntries

  test "a listed reader's place is their own row's, with no row added under the list" do
    board = PointsEntries.board(board(), 9, %{place: 2, balance_micro: 25_000_000})

    assert board.rank == 2
    assert board.you == nil
    assert Enum.map(board.rows, &{&1.rank, &1.you}) == [{1, false}, {2, false}, {2, true}]
  end

  test "a reader below the list gets the place and total from their summary" do
    board = PointsEntries.board(board(), 12, %{place: 14, balance_micro: 5_500_000})

    assert board.rank == 14
    assert board.you == %{rank: 14, points: "5.50"}
    refute Enum.any?(board.rows, & &1.you)
  end

  test "a reader without points, or whose summary is not read yet, has no place" do
    for summary <- [%{place: nil, balance_micro: 0}, nil] do
      board = PointsEntries.board(board(), 12, summary)

      assert board.rank == nil
      assert board.you == nil
      assert length(board.rows) == 3
    end
  end

  # Accounts 8 and 9 are level on points and share second place.
  defp board do
    %{top: [row(7, 1, 40_000_000), row(8, 2, 25_000_000), row(9, 2, 25_000_000)]}
  end

  defp row(id, rank, points) do
    %{
      account_id: id,
      rank: rank,
      points_micro: points,
      name: nil,
      wallet: "0x#{id}",
      ens_name: nil,
      squares: nil,
      picture: nil
    }
  end
end
