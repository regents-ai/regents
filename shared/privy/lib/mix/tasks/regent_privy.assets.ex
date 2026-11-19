defmodule Mix.Tasks.RegentPrivy.Assets do
  @moduledoc "Copies the shared Privy sign-in from this package into the app's `assets/vendor/regent_privy`."
  @shortdoc "Copy the pinned shared Privy sign-in into app assets"
  use Mix.Task
  @impl true
  def run([]) do
    source =
      Mix.Project.deps_paths()
      |> Map.fetch!(:regent_privy)
      |> Path.join("assets")

    destination = Path.join(File.cwd!(), "assets/vendor/regent_privy")
    File.mkdir_p!(destination)

    for file <- Path.wildcard(Path.join(source, "*")) do
      File.cp!(file, Path.join(destination, Path.basename(file)))
    end
  end
end
