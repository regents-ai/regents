defmodule Mix.Tasks.RegentAgentAccess.Assets do
  @shortdoc "Copy the shared signed WebMCP transport into the host's generated assets"
  use Mix.Task

  @impl true
  def run([]) do
    source = Mix.Project.deps_paths() |> Map.fetch!(:regent_agent_access)
    destination = Path.join(File.cwd!(), "assets/vendor/regent_agent_access")
    File.mkdir_p!(destination)

    File.cp!(
      Path.join(source, "assets/signed_tools.ts"),
      Path.join(destination, "signed_tools.ts")
    )
  end
end
