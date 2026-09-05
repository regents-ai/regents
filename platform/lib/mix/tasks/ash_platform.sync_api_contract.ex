defmodule Mix.Tasks.AshPlatform.SyncApiContract do
  use Mix.Task

  @shortdoc "Syncs the canonical API contract to its served location"

  @impl Mix.Task
  def run(args) do
    check? = args == ["--check"]

    unless check? or args == [] do
      Mix.raise("usage: mix ash_platform.sync_api_contract [--check]")
    end

    source = Path.expand("../../../contracts/api-contract.openapiv3.yaml", __DIR__)
    target = Path.expand("../../../priv/static/api-contract.openapiv3.yaml", __DIR__)
    source_bytes = File.read!(source)

    if check? do
      if File.exists?(target) and File.read!(target) == source_bytes do
        Mix.shell().info("API contract is synchronized")
      else
        Mix.raise("served API contract is out of sync")
      end
    else
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, source_bytes)
      Mix.shell().info("Synchronized API contract")
    end
  end
end
