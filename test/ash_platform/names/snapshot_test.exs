defmodule AshPlatform.Names.SnapshotTest do
  use ExUnit.Case, async: true
  alias AshPlatform.Names.Snapshot

  defp snapshot do
    names = ~w(id owner_address ens_tx_hash ens_assigned_at price_wei future_column)

    %{
      "format" => 1,
      "capture" => %{"database" => "synthetic-source", "captured_at" => "2026-09-05T00:00:00Z"},
      "tables" => [
        %{
          "schema" => "platform",
          "table" => "basenames_mints",
          "columns" =>
            Enum.map(
              names,
              &%{"name" => &1, "sql_type" => "text", "nullable" => true, "default" => nil}
            ),
          "primary_key" => ["id"],
          "constraints" => ["PRIMARY KEY (id)"],
          "indexes" => [],
          "sequences" => [],
          "rows" => [
            %{
              "id" => "1",
              "owner_address" => "private-wallet",
              "ens_tx_hash" => nil,
              "ens_assigned_at" => "2024-01-02 03:04:05.123456+00",
              "price_wei" => "123456789012345678901234567890",
              "future_column" => "keep me"
            }
          ]
        }
      ]
    }
  end

  defp change_row(data, fun),
    do: update_in(data, ["tables", Access.at(0), "rows", Access.at(0)], fun)

  test "identical reruns are pure and unknown historical values survive" do
    source = snapshot()
    assert :ok = Snapshot.verify(source, source)
    assert :ok = Snapshot.verify(source, source)
  end

  test "row order is immaterial, but duplicate identities fail" do
    source = snapshot()
    row = get_in(source, ["tables", Access.at(0), "rows", Access.at(0)])
    source = put_in(source, ["tables", Access.at(0), "rows"], [row, %{row | "id" => "2"}])

    assert :ok =
             Snapshot.verify(
               source,
               update_in(source, ["tables", Access.at(0), "rows"], &Enum.reverse/1)
             )

    duplicate = put_in(source, ["tables", Access.at(0), "rows"], [row, row])
    assert {:error, [%{category: "duplicate_primary_key"}]} = Snapshot.verify(source, duplicate)
  end

  test "changed ownership or evidence fails without printing values" do
    source = snapshot()

    candidate =
      change_row(
        source,
        &Map.merge(&1, %{"owner_address" => "other-wallet", "ens_tx_hash" => "private-tx"})
      )

    assert {:error, [problem]} = Snapshot.verify(source, candidate)
    assert problem.columns == ["ens_tx_hash", "owner_address"]
    refute inspect(problem) =~ "private-wallet"
    refute inspect(problem) =~ "private-tx"
  end

  test "missing differs from null and numeric coercion is refused" do
    source = snapshot()

    assert {:error, [%{category: "incomplete_row"}]} =
             Snapshot.verify(source, change_row(source, &Map.delete(&1, "ens_tx_hash")))

    assert {:error, [%{category: "inexact_row_value"}]} =
             Snapshot.verify(source, change_row(source, &Map.put(&1, "price_wei", 1.2)))
  end

  test "missing or extra rows and changed schema stop reconciliation" do
    source = snapshot()
    empty = put_in(source, ["tables", Access.at(0), "rows"], [])
    assert {:error, [%{category: "missing_rows", count: 1}]} = Snapshot.verify(source, empty)
    assert {:error, [%{category: "extra_rows", count: 1}]} = Snapshot.verify(empty, source)
    changed = put_in(source, ["tables", Access.at(0), "constraints"], [])
    assert {:error, [%{category: "schema_conflict"}]} = Snapshot.verify(source, changed)
  end

  test "capture identity may differ but must exist; other metadata is preserved exactly" do
    source = Map.put(snapshot(), "extra", %{"ordinal" => 1})
    candidate = put_in(source, ["capture", "database"], "synthetic-destination")
    assert :ok = Snapshot.verify(source, candidate)
    assert {:error, _} = Snapshot.verify(source, Map.delete(candidate, "capture"))

    assert {:error, [%{category: "snapshot_metadata_conflict"}]} =
             Snapshot.verify(source, Map.delete(candidate, "extra"))

    assert {:error, [%{category: "snapshot_metadata_conflict"}]} =
             Snapshot.verify(source, put_in(candidate, ["extra", "ordinal"], 1.0))

    source = put_in(snapshot(), ["tables", Access.at(0), "extra"], 1)

    assert {:error, [%{category: "schema_conflict"}]} =
             Snapshot.verify(source, put_in(source, ["tables", Access.at(0), "extra"], 1.0))
  end

  test "invalid snapshots never count as matches" do
    for invalid <- [%{}, %{"format" => 1, "tables" => []}, %{"format" => 2, "tables" => []}] do
      assert {:error, _} = Snapshot.verify(invalid, invalid)
    end
  end
end
