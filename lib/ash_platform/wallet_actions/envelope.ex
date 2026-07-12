defmodule AshPlatform.WalletActions.Envelope do
  @moduledoc false

  alias AshPlatform.WalletActions.Address

  @ttl_seconds 600

  def new(action, signer, data, opts \\ []) do
    require_nonempty!(action, :action)
    require_calldata!(data)
    signer = normalize_address!(signer)
    to = Keyword.fetch!(opts, :to) |> normalize_address!()
    value = "0"
    chain_id = 8453
    resource = Keyword.fetch!(opts, :resource)
    contract_name = Keyword.fetch!(opts, :contract_name)
    risk_copy = Keyword.fetch!(opts, :risk_copy)
    require_nonempty!(resource, :resource)
    require_nonempty!(contract_name, :contract_name)
    require_nonempty!(risk_copy, :risk_copy)

    prepared_at = now()

    action_id =
      action_id(
        resource,
        action,
        chain_id,
        to,
        value,
        data,
        signer,
        DateTime.to_iso8601(prepared_at)
      )

    envelope = %{
      action_id: action_id,
      idempotency_key: action_id,
      resource: resource,
      action: action,
      chain_id: chain_id,
      to: to,
      value: value,
      data: String.downcase(data),
      expected_signer: signer,
      prepared_at: DateTime.to_iso8601(prepared_at),
      expires_at: DateTime.add(prepared_at, @ttl_seconds, :second) |> DateTime.to_iso8601(),
      risk_copy: risk_copy,
      approval: Keyword.get(opts, :approval),
      arguments: Keyword.get(opts, :arguments, %{}),
      metadata: %{
        contract_name: contract_name,
        calldata_sha256: sha256(String.downcase(data))
      }
    }

    Map.put(envelope, :confirmation_token, sign(envelope))
  end

  def valid?(envelope, opts \\ [])

  def valid?(envelope, opts) when is_map(envelope) do
    expected_resource = Keyword.fetch!(opts, :resource)
    expected_to = Keyword.fetch!(opts, :to) |> normalize_address!()
    expected_signer = Keyword.fetch!(opts, :signer) |> normalize_address!()
    expected_contract_name = Keyword.fetch!(opts, :contract_name)
    expected_actions = expected_actions!(opts)

    with {:ok, signed} <- verify(field(envelope, :confirmation_token), @ttl_seconds),
         true <- signed == canonical_payload(envelope),
         true <- envelope.chain_id == 8453,
         true <- envelope.value == "0",
         true <- envelope.resource == expected_resource,
         true <- envelope.action in expected_actions,
         true <- envelope.to == expected_to,
         true <- envelope.expected_signer == expected_signer,
         true <- field(envelope.metadata, :contract_name) == expected_contract_name,
         true <- envelope.expected_signer == normalize_address!(envelope.expected_signer),
         true <- envelope.data == String.downcase(envelope.data),
         true <- envelope.action_id == recompute_action_id(envelope),
         true <- envelope.idempotency_key == envelope.action_id,
         {:ok, prepared_at, _offset} <- DateTime.from_iso8601(envelope.prepared_at),
         {:ok, expires_at, _offset} <- DateTime.from_iso8601(envelope.expires_at),
         duration when duration in 1..600 <- DateTime.diff(expires_at, prepared_at, :second),
         :gt <- DateTime.compare(expires_at, now()) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid?(_envelope, _opts), do: false

  def valid_for_confirmation?(envelope, opts \\ [])

  def valid_for_confirmation?(envelope, opts) when is_map(envelope) do
    expected_resource = Keyword.fetch!(opts, :resource)
    expected_to = Keyword.fetch!(opts, :to) |> normalize_address!()
    expected_signer = Keyword.fetch!(opts, :signer) |> normalize_address!()
    expected_contract_name = Keyword.fetch!(opts, :contract_name)
    expected_actions = expected_actions!(opts)

    with {:ok, signed} <- verify(field(envelope, :confirmation_token), @ttl_seconds),
         true <- signed == canonical_payload(envelope),
         true <- envelope.chain_id == 8453,
         true <- envelope.value == "0",
         true <- envelope.resource == expected_resource,
         true <- envelope.action in expected_actions,
         true <- envelope.to == expected_to,
         true <- envelope.expected_signer == expected_signer,
         true <- field(envelope.metadata, :contract_name) == expected_contract_name,
         true <- envelope.expected_signer == normalize_address!(envelope.expected_signer),
         true <- envelope.data == String.downcase(envelope.data),
         true <- envelope.action_id == recompute_action_id(envelope),
         true <- envelope.idempotency_key == envelope.action_id,
         {:ok, prepared_at, _offset} <- DateTime.from_iso8601(envelope.prepared_at),
         {:ok, expires_at, _offset} <- DateTime.from_iso8601(envelope.expires_at),
         duration when duration in 1..600 <- DateTime.diff(expires_at, prepared_at, :second),
         :gt <- DateTime.compare(expires_at, now()) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_for_confirmation?(_envelope, _opts), do: false

  def current_time, do: now()

  defp recompute_action_id(envelope) do
    action_id(
      envelope.resource,
      envelope.action,
      envelope.chain_id,
      envelope.to,
      envelope.value,
      envelope.data,
      envelope.expected_signer,
      envelope.prepared_at
    )
  end

  defp action_id(resource, action, chain_id, to, value, data, signer, prepared_at) do
    [resource, action, chain_id, to, value, data, signer, prepared_at]
    |> Enum.map_join(":", &to_string/1)
    |> sha256()
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp sign(envelope) do
    Phoenix.Token.sign(
      AshPlatformWeb.Endpoint,
      "wallet-action",
      canonical_payload(envelope)
    )
  end

  defp verify(token, max_age) when is_binary(token) do
    Phoenix.Token.verify(AshPlatformWeb.Endpoint, "wallet-action", token, max_age: max_age)
  end

  defp verify(_token, _max_age), do: {:error, :invalid_token}

  defp canonical_payload(envelope) do
    envelope
    |> Map.take([
      :action_id,
      :idempotency_key,
      :resource,
      :action,
      :chain_id,
      :to,
      :value,
      :data,
      :expected_signer,
      :prepared_at,
      :expires_at,
      :risk_copy,
      :approval,
      :arguments,
      :metadata
    ])
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp normalize_address!(value) do
    case Address.normalize(value) do
      {:ok, address} -> address
      :error -> raise ArgumentError, "invalid address"
    end
  end

  defp expected_actions!(opts) do
    case {Keyword.get(opts, :action), Keyword.get(opts, :actions)} do
      {action, nil} when is_binary(action) and action != "" -> [action]
      {nil, actions} when is_list(actions) and actions != [] -> actions
      _ -> raise ArgumentError, "expected action context is required"
    end
  end

  defp require_nonempty!(value, _field) when is_binary(value) and value != "", do: :ok
  defp require_nonempty!(_value, field), do: raise(ArgumentError, "invalid #{field}")

  defp require_calldata!("0x" <> hex)
       when byte_size(hex) > 0 and rem(byte_size(hex), 2) == 0 do
    if String.match?(hex, ~r/^[0-9a-fA-F]+$/), do: :ok, else: raise(ArgumentError, "invalid data")
  end

  defp require_calldata!(_data), do: raise(ArgumentError, "invalid data")

  defp now do
    Application.get_env(:ash_platform, :wallet_action_clock, fn -> DateTime.utc_now() end).()
  end
end
