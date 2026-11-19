defmodule Mix.Tasks.RegentBlog.Stage do
  @shortdoc "Stage a pinned blog package and product content for an application Docker context"
  use Mix.Task
  @entries ~w(lib priv mix.exs)

  def run([]) do
    source = Mix.Project.deps_paths() |> Map.fetch!(:regent_blog)
    snapshot = Path.dirname(source)
    revision = System.get_env("REGENT_BLOG_REVISION")

    unless is_binary(revision) and Regex.match?(~r/\A[0-9a-f]{40}\z/, revision) and
             File.read(Path.join(snapshot, ".regent-revision")) == {:ok, revision <> "\n"} do
      Mix.raise("Stage requires a pinned elixir-utils snapshot and REGENT_BLOG_REVISION")
    end

    expected = snapshot |> Path.join(".regent-files.json") |> File.read!() |> Jason.decode!()

    expected =
      expected
      |> Map.filter(fn {name, _} ->
        Enum.any?(@entries, &(name == "blog/#{&1}" or String.starts_with?(name, "blog/#{&1}/")))
      end)
      |> Map.new(fn {name, value} -> {String.replace_prefix(name, "blog/", ""), value} end)

    actual =
      source
      |> files(@entries)
      |> Map.new(fn {relative, path} ->
        {relative, %{"kind" => "file", "sha256" => digest(File.read!(path))}}
      end)

    unless map_size(expected) > 0 and actual == expected,
      do: Mix.raise("Blog package differs from its pinned snapshot")

    content = Path.expand("../blog")
    RegentBlog.load!(content)
    stage!(source, @entries, "regent_blog", revision, expected)
    # These are builder inputs, never a public static directory.
    stage!(content, File.ls!(content), "regent_blog_content", revision)
    Mix.shell().info("Staged pinned blog package and product content; no deployment performed")
  end

  defp stage!(source, entries, name, revision, expected \\ nil) do
    destination = Path.expand("vendor/#{name}")
    marker = ".regent-blog-generated"

    case File.lstat(destination) do
      {:error, :enoent} ->
        :ok

      {:ok, %{type: :directory}} ->
        unless File.regular?(Path.join(destination, marker)),
          do: Mix.raise("Refusing unrecognized #{destination}")

      _ ->
        Mix.raise("Refusing non-directory #{destination}")
    end

    id = Integer.to_string(System.system_time(:nanosecond))
    staging = Path.expand("vendor/.regent-blog-stage-#{name}-#{id}")
    File.mkdir_p!(staging)

    for {relative, path} <- files(source, entries) do
      target = Path.join(staging, relative)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(path, target)
    end

    if expected do
      staged =
        staging
        |> files(@entries)
        |> Map.new(fn {relative, path} ->
          {relative, %{"kind" => "file", "sha256" => digest(File.read!(path))}}
        end)

      unless staged == expected,
        do: Mix.raise("Blog package changed during staging; candidate preserved")
    end

    File.write!(Path.join(staging, marker), revision <> "\n")

    if File.exists?(destination) do
      history = Path.expand("vendor/.regent-blog-history")
      File.mkdir_p!(history)
      File.rename!(destination, Path.join(history, "#{name}-#{id}"))
    end

    File.rename!(staging, destination)
  end

  defp files(root, entries) do
    Enum.flat_map(entries, fn relative ->
      if Enum.any?(Path.split(relative), &Regex.match?(~r/\A\.env/i, &1)),
        do: Mix.raise("Refusing environment-shaped blog input")

      path = Path.join(root, relative)

      case File.lstat!(path).type do
        :directory -> files(root, Enum.map(File.ls!(path), &Path.join(relative, &1)))
        :regular -> [{relative, path}]
        _ -> Mix.raise("Blog staging requires regular files, not symlinks")
      end
    end)
  end

  defp digest(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
