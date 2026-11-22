defmodule Regents.Autolaunch.LabRpc do
  @moduledoc false

  def opts(config, scope \\ "autolaunch local lab") do
    [
      rpc_url: config.rpc_url,
      expected_chain_id: config.chain_id,
      log_scope: scope
    ]
  end
end
