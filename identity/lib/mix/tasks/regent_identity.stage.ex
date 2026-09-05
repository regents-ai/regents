defmodule Mix.Tasks.RegentIdentity.Stage do
  @shortdoc "Stage pinned shared identity and Privy packages for a release context"
  use Mix.Task

  @impl true
  def run([]) do
    paths = Mix.Project.deps_paths()

    for {dependency, directory, variable} <- [
          {:regent_identity, "identity", "REGENT_IDENTITY_REVISION"},
          {:regent_privy, "privy", "REGENT_PRIVY_REVISION"}
        ] do
      stage(
        Map.fetch!(paths, dependency),
        directory,
        Atom.to_string(dependency),
        System.get_env(variable)
      )
    end
  end

  defp stage(source, directory, package, revision) do
    parent = Path.dirname(source)

    unless is_binary(revision) and Regex.match?(~r/\A[0-9a-f]{40}\z/, revision) and
             File.read(Path.join(parent, ".regent-revision")) == {:ok, revision <> "\n"} do
      Mix.raise("#{package} requires its pinned workspace snapshot and revision")
    end

    entries = ~w(lib assets priv mix.exs .formatter.exs)

    expected =
      parent
      |> Path.join(".regent-files.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.filter(fn {name, _} ->
        Enum.any?(
          entries,
          &(name == "#{directory}/#{&1}" or String.starts_with?(name, "#{directory}/#{&1}/"))
        )
      end)
      |> Map.new(fn {name, value} ->
        {String.replace_prefix(name, "#{directory}/", ""), value}
      end)

    destination_name = if package == "regent_privy", do: "regent_privy_shared", else: package
    destination = Path.expand("vendor/#{destination_name}")
    marker = ".regent-identity-generated"

    if File.exists?(destination) and not File.regular?(Path.join(destination, marker)),
      do: Mix.raise("Refusing to replace an unrecognized #{package} directory")

    case File.lstat(destination) do
      {:ok, %{type: :symlink}} -> Mix.raise("Refusing a symlinked staging destination")
      _ -> :ok
    end

    id = Integer.to_string(System.system_time(:nanosecond))
    staging = Path.expand("vendor/.regent-identity-stage-#{package}-#{id}")
    File.mkdir_p!(staging)

    for entry <- entries, File.exists?(Path.join(source, entry)) do
      File.cp_r!(Path.join(source, entry), Path.join(staging, entry), dereference_symlinks: false)
    end

    actual =
      staging
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&(File.lstat!(&1).type == :directory))
      |> Map.new(fn path ->
        unless File.lstat!(path).type == :regular,
          do: Mix.raise("Package must contain regular files only")

        digest = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
        {Path.relative_to(path, staging), %{"kind" => "file", "sha256" => digest}}
      end)

    unless map_size(expected) > 0 and actual == expected,
      do:
        Mix.raise("#{package} differs from its pinned snapshot; staging preserved for inspection")

    File.write!(Path.join(staging, marker), Jason.encode!(%{revision: revision, files: actual}))

    if File.exists?(destination) do
      history = Path.expand("vendor/.regent-identity-history")
      File.mkdir_p!(history)
      File.rename!(destination, Path.join(history, "#{package}-#{id}"))
    end

    File.rename!(staging, destination)
    Mix.shell().info("Staged #{package} at #{revision}; no migration or deployment performed")
  end
end
