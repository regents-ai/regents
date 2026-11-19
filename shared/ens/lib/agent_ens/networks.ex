defmodule AgentEns.Networks do
  @moduledoc """
  Built-in network defaults used by verification and link preparation helpers.

  Callers can override any shipped values through the application environment.
  """

  @defaults %{
    1 => %{
      ens_registry: "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e",
      name_wrapper: "0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401",
      reverse_registrar: "0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb",
      erc8004_registry: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
    },
    11_155_111 => %{
      ens_registry: "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e",
      name_wrapper: "0x0635513f179D50A207757E05759CbD106d7dFcE8",
      reverse_registrar: "0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6",
      erc8004_registry: "0x8004A818BFB912233c491871b3d84c89A494BD9e"
    }
  }

  @spec defaults() :: map()
  def defaults, do: @defaults

  @spec get(non_neg_integer()) :: map() | nil
  def get(chain_id) when is_integer(chain_id) and chain_id >= 0 do
    app_overrides =
      Application.get_env(:ens_elixir, :networks, %{})
      |> Map.new(fn
        {key, value} when is_binary(key) -> {String.to_integer(key), value}
        {key, value} -> {key, value}
      end)

    app_overrides
    |> Map.get(chain_id, %{})
    |> then(&Map.merge(Map.get(@defaults, chain_id, %{}), &1))
    |> case do
      value when map_size(value) == 0 -> nil
      value -> value
    end
  end
end
