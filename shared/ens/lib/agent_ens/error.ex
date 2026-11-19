defmodule AgentEns.Error do
  @moduledoc """
  Structured error used throughout the package.

  Public functions in `ens_elixir` return `{:error, %AgentEns.Error{}}` instead
  of raising. The `kind` tells you the broad category and `message` is safe to
  surface in logs, CLI output, or review flows.
  """

  @enforce_keys [:kind, :message]
  defstruct [:kind, :message, details: %{}]

  @type kind ::
          :invalid_argument
          | :not_found
          | :unsupported
          | :unauthorized
          | :io
          | :internal

  @type raw_reason ::
          {:buffer_too_short, non_neg_integer()}
          | {:unsupported_version, non_neg_integer()}
          | {:truncated_payload, non_neg_integer(), non_neg_integer()}
          | :empty_address
          | {:hex_decode, String.t()}
          | {:invalid_address, String.t()}
          | {:invalid_agent_id, String.t()}
          | {:invalid_agent_id_type, term()}
          | {:invalid_ens_name, term()}
          | {:normalization_failed, term()}
          | {:rpc_error, term()}
          | {:invalid_rpc_result, term()}
          | {:unsupported_network, term()}
          | :resolver_not_found
          | {:resolver_interface_unsupported, String.t()}
          | {:manager_mismatch, %{expected: String.t() | nil, signer: String.t() | nil}}
          | {:wrapped_name_owner_lookup_failed, term()}
          | :unsupported_offchain_resolver
          | {:erc8004_registration_fetch_failed, term()}
          | {:erc8004_registration_parse_failed, term()}
          | {:publisher_failed, term()}
          | {:invalid_tx_request, term()}
          | {:unsupported_uri_scheme, String.t()}
          | {:invalid_data_uri, term()}
          | {:unsupported_content_type, String.t()}
          | {:not_found, term()}
          | {:unauthorized, term()}
          | {:invalid_argument, String.t(), term()}
          | {:unexpected_state, term()}
          | {:missing_required_input, String.t()}
          | {:abi_error, term()}
          | {:resolver_call_failed, term()}
          | {:offchain_resolver_detected, String.t()}
          | {:erc8004_write_forbidden, term()}

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          details: map()
        }

  @spec new(raw_reason()) :: t()
  def new(reason), do: from_reason(reason)

  @spec invalid_argument(String.t(), map()) :: t()
  def invalid_argument(message, details \\ %{}),
    do: %__MODULE__{kind: :invalid_argument, message: message, details: details}

  @spec not_found(String.t(), map()) :: t()
  def not_found(message, details \\ %{}),
    do: %__MODULE__{kind: :not_found, message: message, details: details}

  @spec unsupported(String.t(), map()) :: t()
  def unsupported(message, details \\ %{}),
    do: %__MODULE__{kind: :unsupported, message: message, details: details}

  @spec unauthorized(String.t(), map()) :: t()
  def unauthorized(message, details \\ %{}),
    do: %__MODULE__{kind: :unauthorized, message: message, details: details}

  @spec io(String.t(), map()) :: t()
  def io(message, details \\ %{}), do: %__MODULE__{kind: :io, message: message, details: details}

  @spec internal(String.t(), map()) :: t()
  def internal(message, details \\ %{}),
    do: %__MODULE__{kind: :internal, message: message, details: details}

  defp from_reason({:buffer_too_short, len}) do
    invalid_argument("erc7930: buffer too short (need at least 6 bytes, got #{len})", %{
      length: len
    })
  end

  defp from_reason({:unsupported_version, version}) do
    unsupported(
      "erc7930: unsupported version 0x#{Integer.to_string(version, 16) |> String.pad_leading(4, "0")}",
      %{version: version}
    )
  end

  defp from_reason({:truncated_payload, expected, available}) do
    invalid_argument(
      "erc7930: truncated payload (expected #{expected} bytes, have #{available})",
      %{expected: expected, available: available}
    )
  end

  defp from_reason(:empty_address),
    do: invalid_argument("erc7930: both chain reference and address are empty")

  defp from_reason({:hex_decode, reason}),
    do: invalid_argument("hex decode error: #{reason}", %{reason: reason})

  defp from_reason({:invalid_address, value}),
    do: invalid_argument("invalid address: #{inspect(value)}", %{value: value})

  defp from_reason({:invalid_agent_id, agent_id}),
    do:
      invalid_argument("agent id must not contain '[' or ']': #{inspect(agent_id)}", %{
        agent_id: agent_id
      })

  defp from_reason({:invalid_agent_id_type, value}),
    do:
      invalid_argument("agent id must be a string or non-negative integer: #{inspect(value)}", %{
        value: value
      })

  defp from_reason({:invalid_ens_name, value}),
    do: invalid_argument("invalid ENS name: #{inspect(value)}", %{value: value})

  defp from_reason({:normalization_failed, reason}),
    do:
      invalid_argument("ENS normalization failed: #{inspect(reason)}", %{reason: inspect(reason)})

  defp from_reason({:rpc_error, reason}),
    do: io("rpc error: #{inspect(reason)}", %{reason: inspect(reason)})

  defp from_reason({:invalid_rpc_result, result}),
    do: internal("invalid rpc result: #{inspect(result)}", %{result: inspect(result)})

  defp from_reason({:unsupported_network, network}),
    do: unsupported("unsupported network: #{inspect(network)}", %{network: inspect(network)})

  defp from_reason(:resolver_not_found), do: not_found("ENS resolver not found")

  defp from_reason({:resolver_interface_unsupported, resolver}),
    do:
      unsupported("resolver does not support text-record writes: #{resolver}", %{
        resolver: resolver
      })

  defp from_reason({:manager_mismatch, %{expected: expected, signer: signer} = details}),
    do:
      unauthorized(
        "signer #{inspect(signer)} does not control ENS name managed by #{inspect(expected)}",
        details
      )

  defp from_reason({:wrapped_name_owner_lookup_failed, reason}),
    do:
      io("failed to determine wrapped ENS name owner: #{inspect(reason)}", %{
        reason: inspect(reason)
      })

  defp from_reason(:unsupported_offchain_resolver),
    do: unsupported("resolver uses offchain or unsupported write semantics")

  defp from_reason({:erc8004_registration_fetch_failed, reason}),
    do:
      io("failed to fetch ERC-8004 registration: #{inspect(reason)}", %{reason: inspect(reason)})

  defp from_reason({:erc8004_registration_parse_failed, reason}),
    do:
      invalid_argument("failed to parse ERC-8004 registration: #{inspect(reason)}", %{
        reason: inspect(reason)
      })

  defp from_reason({:publisher_failed, reason}),
    do:
      io("failed to publish ERC-8004 registration: #{inspect(reason)}", %{reason: inspect(reason)})

  defp from_reason({:invalid_tx_request, reason}),
    do:
      invalid_argument("invalid transaction request: #{inspect(reason)}", %{
        reason: inspect(reason)
      })

  defp from_reason({:unsupported_uri_scheme, scheme}),
    do: unsupported("unsupported URI scheme: #{inspect(scheme)}", %{scheme: scheme})

  defp from_reason({:invalid_data_uri, reason}),
    do: invalid_argument("invalid data URI: #{inspect(reason)}", %{reason: inspect(reason)})

  defp from_reason({:unsupported_content_type, type}),
    do: unsupported("unsupported content type: #{inspect(type)}", %{content_type: type})

  defp from_reason({:not_found, value}),
    do: not_found("not found: #{inspect(value)}", %{value: inspect(value)})

  defp from_reason({:unauthorized, value}),
    do: unauthorized("unauthorized: #{inspect(value)}", %{value: inspect(value)})

  defp from_reason({:invalid_argument, name, value}),
    do:
      invalid_argument("invalid argument #{name}: #{inspect(value)}", %{
        name: name,
        value: inspect(value)
      })

  defp from_reason({:unexpected_state, state}),
    do: internal("unexpected state: #{inspect(state)}", %{state: inspect(state)})

  defp from_reason({:missing_required_input, name}),
    do: invalid_argument("missing required input: #{name}", %{name: name})

  defp from_reason({:abi_error, reason}),
    do: internal("abi error: #{inspect(reason)}", %{reason: inspect(reason)})

  defp from_reason({:resolver_call_failed, reason}),
    do: io("resolver call failed: #{inspect(reason)}", %{reason: inspect(reason)})

  defp from_reason({:offchain_resolver_detected, resolver}),
    do: unsupported("resolver #{resolver} appears to be offchain-only", %{resolver: resolver})

  defp from_reason({:erc8004_write_forbidden, reason}),
    do:
      unauthorized("erc-8004 update is not authorized: #{inspect(reason)}", %{
        reason: inspect(reason)
      })
end
