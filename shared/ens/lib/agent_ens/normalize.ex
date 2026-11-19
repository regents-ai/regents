defmodule AgentEns.Normalize do
  @moduledoc """
  ENS name normalization helpers.

  This module applies UTS-46 compatibility processing through the Erlang `:idna`
  implementation, then returns the normalized Unicode name used for namehashing
  and ENS record access.
  """

  alias AgentEns.Error

  @type normalized_name :: String.t()

  # UTS #46 with its STD3 rule: in ASCII only letters, digits and hyphens.
  @idna [:uts46, :std3_rules]

  @spec normalize(String.t()) :: {:ok, normalized_name()} | {:error, Error.t()}
  def normalize(name) when is_binary(name) do
    normalized =
      name
      |> String.trim()
      |> String.trim_trailing(".")

    cond do
      normalized == "" ->
        {:error, Error.new({:invalid_ens_name, name})}

      String.contains?(normalized, ["[", "]"]) ->
        {:error, Error.new({:invalid_ens_name, name})}

      true ->
        try do
          normalized_unicode =
            normalized
            |> String.to_charlist()
            |> :idna.encode(@idna)
            |> :idna.decode(@idna)
            |> List.to_string()

          if normalized_unicode == "" do
            {:error, Error.new({:invalid_ens_name, name})}
          else
            {:ok, normalized_unicode}
          end
        catch
          kind, reason ->
            {:error, Error.new({:normalization_failed, {kind, reason}})}
        end
    end
  end

  def normalize(value), do: {:error, Error.new({:invalid_ens_name, value})}
end
