defmodule AgentEns.Internal.Validation do
  @moduledoc false

  # Shared input validation for map-based public entry points.
  #
  # All helpers read atom-keyed params maps and return `{:ok, value}` or
  # `{:error, %AgentEns.Error{}}`.

  alias AgentEns.Error

  @spec required_binary(map(), atom()) :: {:ok, String.t()} | {:error, Error.t()}
  def required_binary(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  @spec required_integer(map(), atom()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def required_integer(params, key) do
    case Map.get(params, key) do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 -> {:ok, parsed}
          _ -> {:error, Error.new({:invalid_argument, Atom.to_string(key), value})}
        end

      value ->
        {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  @spec optional_integer(map(), atom(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def optional_integer(params, key, default) do
    case Map.get(params, key) do
      nil -> {:ok, default}
      _value -> required_integer(params, key)
    end
  end

  @spec required_agent_id(map()) ::
          {:ok, non_neg_integer() | String.t()} | {:error, Error.t()}
  def required_agent_id(params) do
    case Map.get(params, :agent_id) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, Error.new({:invalid_agent_id_type, value})}
    end
  end

  # Address normalization for optional inputs: well-formed addresses come back
  # trimmed and lowercased, everything else maps to nil.
  @spec normalize_address(term()) :: String.t() | nil
  def normalize_address(value), do: AgentEns.Address.normalize(value)
end
