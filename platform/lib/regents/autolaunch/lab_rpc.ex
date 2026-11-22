defmodule Regents.Autolaunch.LabRpc do
  @moduledoc false

  def opts(config, scope \\ "autolaunch local lab"), do: [chain_id: config.chain_id, scope: scope]
end
