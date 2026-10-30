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
    assert PaperProDaily.list_papers!([tomorrow]) == []
    assert PaperProDaily.export_papers!() == []
    assert PaperProDaily.get_picture!(paper.id) == nil
  end

  test "all reads include today and the past but exclude future dates" do
    today = Date.utc_today()
    yesterday = paper_fixture!(Date.add(today, -1))
    current = paper_fixture!(today)
    future = paper_fixture!(Date.add(today, 1))
    expected = [current.id, yesterday.id]

    dates = [future.date, today, yesterday.date]
    assert Enum.map(PaperProDaily.list_papers!(dates), & &1.id) == expected
    assert Enum.map(PaperProDaily.export_papers!(), & &1.id) == expected
    assert PaperProDaily.get_picture!(current.id).picture == current.picture
    assert PaperProDaily.get_picture!(future.id) == nil

    # Publication is part of the read query, not an optional authorization check.
    assert Enum.map(PaperProDaily.export_papers!(authorize?: false), & &1.id) == expected
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

  test "a paper is saved with one to three of the page's tags" do
    today = Date.utc_today()
    paper = paper_fixture!(today, %{tags: ["Safety", "Memory", "Science"]})
    assert paper.tags == ["Safety", "Memory", "Science"]

    for tags <- [nil, [], ["Safety", "Memory", "Science", "Swarms"], ["Gossip"]] do
      assert_raise Ash.Error.Invalid, fn -> paper_fixture!(today, %{tags: tags}) end
    end
  end

  test "papers are tagged all at once, or not at all" do
    today = Date.utc_today()
    first = paper_fixture!(today, %{arxiv_url: "https://arxiv.org/abs/2610.00001"})
    second = paper_fixture!(today, %{arxiv_url: "https://arxiv.org/abs/2610.00002"})
    future = paper_fixture!(Date.add(today, 1))
    system = [actor: %Regents.Actors.System{}]

    assert PaperProDaily.tag_papers!(
             %{first.id => ["Economics"], second.id => ["Safety", "Training"]},
             system
           ) == 2

    assert Enum.map(PaperProDaily.export_papers!(), &{&1.id, &1.tags}) == [
             {first.id, ["Economics"]},
             {second.id, ["Safety", "Training"]}
           ]

    # An unknown tag, or a paper that is not yet public, leaves every paper as it was.
    for {error, tags} <- [
          {Ash.Error.Invalid, %{first.id => ["Memory"], second.id => ["Gossip"]}},
          {Ash.Error.Unknown, %{first.id => ["Memory"], future.id => ["Memory"]}}
        ] do
      assert_raise error, fn -> PaperProDaily.tag_papers!(tags, system) end
      assert PaperProDaily.get_paper!(first.id).tags == ["Economics"]
    end

    assert_raise Ash.Error.Forbidden, fn ->
      PaperProDaily.tag_papers!(%{first.id => ["Memory"]})
    end
  end

  defp papers_at(now) do
    Paper
    |> Publication.published_query(now)
    |> Ash.Query.for_read(:export)
    |> Ash.read!()
  end
end
