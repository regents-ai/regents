defmodule Regents.PaperProDailyTest do
  use RegentsWeb.ConnCase, async: false

  alias Regents.PaperProDaily
  alias Regents.PaperProDaily.{Paper, Publication}

  import Regents.PaperProDailyFixtures

  test "future papers can be written and replaced without becoming public" do
    tomorrow = Date.add(Date.utc_today(), 1)
    paper = paper_fixture!(tomorrow)
    updated = paper_fixture!(tomorrow, %{title: "Scheduled replacement"})

    assert updated.id == paper.id
    assert updated.title == "Scheduled replacement"
    assert PaperProDaily.list_papers!().results == []
    assert PaperProDaily.export_papers!() == []
    assert PaperProDaily.get_picture!(tomorrow) == nil
  end

  test "all reads include today and the past but exclude future dates" do
    today = Date.utc_today()
    yesterday = paper_fixture!(Date.add(today, -1))
    current = paper_fixture!(today)
    future = paper_fixture!(Date.add(today, 1))
    expected = [current.id, yesterday.id]

    assert Enum.map(PaperProDaily.list_papers!().results, & &1.id) == expected
    assert Enum.map(PaperProDaily.export_papers!(), & &1.id) == expected
    assert PaperProDaily.get_picture!(today).picture == current.picture
    assert PaperProDaily.get_picture!(future.date) == nil

    # Publication is part of the read query, not an optional authorization check.
    assert Enum.map(PaperProDaily.export_papers!(authorize?: false), & &1.id) == expected
  end

  test "pagination filters scheduled papers before applying the offset and limit" do
    today = Date.utc_today()
    papers = Enum.map(0..7, &paper_fixture!(Date.add(today, -&1)))
    paper_fixture!(Date.add(today, 1))

    first = PaperProDaily.list_papers!(page: [offset: 0, limit: 6])
    second = PaperProDaily.list_papers!(page: [offset: 6, limit: 6])

    assert first.more?
    refute second.more?
    assert Enum.map(first.results ++ second.results, & &1.id) == Enum.map(papers, & &1.id)
  end

  test "the same stored paper becomes eligible exactly at UTC midnight" do
    previous = paper_fixture!(~D[2000-12-31])
    next = paper_fixture!(~D[2001-01-01])

    before_midnight = papers_at(~U[2000-12-31 23:59:59.999999Z])
    at_midnight = papers_at(~U[2001-01-01 00:00:00Z])

    assert Enum.map(before_midnight, & &1.id) == [previous.id]
    assert Enum.map(at_midnight, & &1.id) == [next.id, previous.id]
  end

  test "UTC cutoff is independent of the offset in an input timestamp" do
    previous = paper_fixture!(~D[2000-12-31])
    next = paper_fixture!(~D[2001-01-01])
    {:ok, before_midnight, -14_400} = DateTime.from_iso8601("2000-12-31T19:59:59.999999-04:00")
    {:ok, at_midnight, -14_400} = DateTime.from_iso8601("2000-12-31T20:00:00-04:00")

    assert Enum.map(papers_at(before_midnight), & &1.id) == [previous.id]
    assert Enum.map(papers_at(at_midnight), & &1.id) == [next.id, previous.id]
  end

  test "the midnight timer rounds up and handles year and leap-day boundaries" do
    for {now, expected} <- [
          {~U[2000-12-31 23:59:59.999999Z], 1},
          {~U[2001-01-01 00:00:00Z], 86_400_000},
          {~U[2028-02-28 23:59:59.500000Z], 500},
          {~U[2028-02-29 23:59:59.998999Z], 2},
          {~U[2026-10-10 12:00:00Z], 43_200_000}
        ] do
      assert Publication.milliseconds_until_midnight(now) == expected
    end
  end

  defp papers_at(now) do
    Paper
    |> Publication.published_query(now)
    |> Ash.Query.for_read(:export)
    |> Ash.read!()
  end
end
