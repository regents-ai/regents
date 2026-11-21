defmodule Regents.Autolaunch.LabRpc do
  @moduledoc false

  alias Regents.Chain.Rpc

  def opts(config, scope \\ "autolaunch local lab") do
    [
      rpc_url: config.rpc_url,
      expected_chain_id: config.chain_id,
      log_scope: scope
    ]
  end

  def block_from_logs(logs) when is_list(logs) do
    case logs |> Enum.map(& &1["blockHash"]) |> Enum.uniq() do
      [hash] when is_binary(hash) ->
        if Rpc.valid_hash?(hash),
          do: {:ok, %{hash: String.downcase(hash)}},
          else: {:error, :invalid_receipt}

      _other ->
        {:error, :invalid_receipt}
    end
  end
end
