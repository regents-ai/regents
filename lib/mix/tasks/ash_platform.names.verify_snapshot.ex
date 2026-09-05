defmodule Mix.Tasks.AshPlatform.Names.VerifySnapshot do
  @shortdoc "Compare complete local claim snapshots without starting the application"
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: [source: :string, candidate: :string]) do
      {[source: source, candidate: candidate], [], []} -> verify(source, candidate)
      {[candidate: candidate, source: source], [], []} -> verify(source, candidate)
      _ -> Mix.raise("Use --source snapshot.json --candidate snapshot.json")
    end
  end

  defp verify(source, candidate) do
    # Compile modules only: no app.start and no database operations.
    Mix.Task.run("compile")

    case AshPlatform.Names.Snapshot.verify(read!(source), read!(candidate)) do
      :ok -> Mix.shell().info("PASS: supplied schemas and complete row values match")
      {:error, problems} -> Mix.raise(Jason.encode!(%{status: "conflict", problems: problems}))
    end
  end

  defp read!(path) do
    if Path.extname(path) != ".json", do: Mix.raise("Snapshots must be JSON files")

    with {:ok, bytes} <- File.read(path),
         {:ok, snapshot} <- Jason.decode(bytes, objects: :ordered_objects) do
      exact_object!(snapshot)
    else
      _ -> Mix.raise("Cannot read a valid JSON snapshot (contents omitted)")
    end
  end

  defp exact_object!(%Jason.OrderedObject{values: values}) do
    keys = Enum.map(values, &elem(&1, 0))

    if length(keys) != length(Enum.uniq(keys)),
      do: Mix.raise("Duplicate JSON object keys (contents omitted)")

    Map.new(values, fn {key, value} -> {key, exact_object!(value)} end)
  end

  defp exact_object!(values) when is_list(values), do: Enum.map(values, &exact_object!/1)
  defp exact_object!(value), do: value
end
