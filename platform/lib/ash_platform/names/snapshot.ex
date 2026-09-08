defmodule AshPlatform.Names.Snapshot do
  @moduledoc """
  Offline comparison of complete historical-claim snapshots. This does not connect
  to a database, import records, or prove that an exporter captured the source.

  Row values are exact PostgreSQL text representations or nil. Column metadata
  carries SQL types. Unknown columns and metadata are compared, never discarded.
  Reports contain categories, table names and column names, never row values.
  """

  @spec verify(map(), map()) :: :ok | {:error, [map()]}
  def verify(source, candidate) do
    with {:ok, source_tables} <- validate(source, "source"),
         {:ok, candidate_tables} <- validate(candidate, "candidate") do
      metadata = Map.drop(source, ["tables", "capture"])
      candidate_metadata = Map.drop(candidate, ["tables", "capture"])

      problems =
        if metadata === candidate_metadata,
          do: compare_tables(source_tables, candidate_tables),
          else: [%{category: "snapshot_metadata_conflict"}]

      if problems == [], do: :ok, else: {:error, problems}
    end
  end

  defp validate(
         %{
           "format" => 1,
           "capture" => %{"database" => database, "captured_at" => captured_at},
           "tables" => tables
         },
         side
       )
       when is_binary(database) and database != "" and is_binary(captured_at) and
              captured_at != "" and is_list(tables) and tables != [] do
    Enum.reduce_while(tables, {:ok, %{}}, fn table, {:ok, indexed} ->
      case validate_table(table) do
        {:ok, name, _data} when is_map_key(indexed, name) ->
          {:halt, error("duplicate_table", side, name)}

        {:ok, name, data} ->
          {:cont, {:ok, Map.put(indexed, name, data)}}

        {:error, category} ->
          {:halt, error(category, side)}
      end
    end)
  end

  defp validate(_, side), do: error("invalid_snapshot", side)

  defp validate_table(
         %{
           "schema" => schema,
           "table" => table,
           "columns" => columns,
           "primary_key" => primary_key,
           "rows" => rows
         } = data
       )
       when is_binary(schema) and is_binary(table) and is_list(columns) and
              is_list(primary_key) and is_list(rows) do
    with true <- table_shape?(schema, table, columns, primary_key, data),
         true <- Enum.all?(columns, &valid_column?/1),
         names = Enum.map(columns, & &1["name"]),
         true <- unique?(names) and unique?(primary_key),
         true <- Enum.all?(primary_key, &(&1 in names)),
         {:ok, indexed_rows} <- index_rows(rows, names, primary_key) do
      {:ok, {schema, table}, {Map.delete(data, "rows"), indexed_rows}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "invalid_table_metadata"}
    end
  end

  defp validate_table(_), do: {:error, "invalid_table_metadata"}

  defp table_shape?(schema, table, columns, primary_key, data) do
    schema != "" and table != "" and columns != [] and primary_key != [] and
      Enum.all?(~w(constraints indexes sequences), &is_list(data[&1]))
  end

  defp unique?(list), do: length(list) == length(Enum.uniq(list))

  defp valid_column?(%{
         "name" => name,
         "sql_type" => type,
         "nullable" => nullable,
         "default" => default
       }) do
    is_binary(name) and name != "" and is_binary(type) and type != "" and
      is_boolean(nullable) and (is_nil(default) or is_binary(default))
  end

  defp valid_column?(_), do: false

  defp index_rows(rows, names, primary_key) do
    Enum.reduce_while(rows, {:ok, %{}}, fn row, {:ok, indexed} ->
      case row_problem(row, names, primary_key, indexed) do
        nil -> {:cont, {:ok, Map.put(indexed, Enum.map(primary_key, &row[&1]), row)}}
        category -> {:halt, {:error, category}}
      end
    end)
  end

  defp row_problem(row, names, primary_key, indexed) do
    cond do
      not is_map(row) or MapSet.new(Map.keys(row)) != MapSet.new(names) -> "incomplete_row"
      not Enum.all?(Map.values(row), &(is_binary(&1) or is_nil(&1))) -> "inexact_row_value"
      Enum.any?(primary_key, &is_nil(row[&1])) -> "null_primary_key"
      Map.has_key?(indexed, Enum.map(primary_key, &row[&1])) -> "duplicate_primary_key"
      true -> nil
    end
  end

  defp compare_tables(source, candidate) do
    (Map.keys(source) ++ Map.keys(candidate))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      # A repeated variable in a pattern matches by strict equality, so 1 and 1.0
      # metadata still conflict exactly as `===` compares them.
      case {Map.fetch(source, name), Map.fetch(candidate, name)} do
        {{:ok, _}, :error} ->
          [problem("missing_table", name)]

        {:error, {:ok, _}} ->
          [problem("extra_table", name)]

        {{:ok, {metadata, rows}}, {:ok, {metadata, other_rows}}} ->
          compare_rows(name, rows, other_rows)

        {{:ok, _}, {:ok, _}} ->
          [problem("schema_conflict", name)]
      end
    end)
  end

  defp compare_rows(name, source, candidate) do
    missing = Map.keys(source) -- Map.keys(candidate)
    extra = Map.keys(candidate) -- Map.keys(source)

    changed =
      Enum.flat_map(source, fn {key, row} ->
        case Map.fetch(candidate, key) do
          {:ok, other} when other != row ->
            fields = row |> Map.keys() |> Enum.filter(&(row[&1] != other[&1])) |> Enum.sort()
            [Map.put(problem("row_conflict", name), :columns, fields)]

          _ ->
            []
        end
      end)

    count_problem("missing_rows", name, missing) ++
      count_problem("extra_rows", name, extra) ++ changed
  end

  defp count_problem(_, _, []), do: []

  defp count_problem(category, name, rows),
    do: [Map.put(problem(category, name), :count, length(rows))]

  defp problem(category, {schema, table}), do: %{category: category, schema: schema, table: table}
  defp error(category, side), do: {:error, [%{category: category, side: side}]}
  defp error(category, side, name), do: {:error, [Map.put(problem(category, name), :side, side)]}
end
