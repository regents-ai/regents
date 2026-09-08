defmodule Mix.Tasks.RegentIdentity.Assets do
  @shortdoc "Copy the pinned shared profile client into product assets"
  use Mix.Task
  @impl true
  def run([]) do
    source =
      Mix.Project.deps_paths()
      |> Map.fetch!(:regent_identity)
      |> Path.join("assets")

    destination = Path.join(File.cwd!(), "assets/vendor/regent_identity")
    File.mkdir_p!(destination)

    for file <- Path.wildcard(Path.join(source, "*")) do
      File.cp!(file, Path.join(destination, Path.basename(file)))
    end
  end
end
