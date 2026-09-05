defmodule Mix.Tasks.AshPlatform.RouteHandoff do
  @shortdoc "Writes or checks the generated founder-shell route handoff"

  use Mix.Task

  @json_path "priv/handoff/founder-shell-route-catalog.json"
  @digest_path "priv/handoff/founder-shell-route-catalog.sha256"

  @impl Mix.Task
  def run(args) do
    handoff = AshPlatformWeb.RouteCatalog.design_handoff()
    expected = %{@json_path => handoff.json, @digest_path => handoff.digest <> "\n"}

    if "--check" in args do
      check!(expected)
    else
      write!(expected)
    end
  end

  defp check!(expected) do
    stale = Enum.reject(expected, fn {path, contents} -> File.read(path) == {:ok, contents} end)

    if stale == [] do
      IO.puts("Founder-shell route handoff is current")
    else
      paths = Enum.map_join(stale, ", ", &elem(&1, 0))
      Mix.raise("Founder-shell route handoff is stale: #{paths}")
    end
  end

  defp write!(expected) do
    Enum.each(expected, fn {path, contents} ->
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, contents)
      IO.puts("Wrote #{path}")
    end)
  end
end
