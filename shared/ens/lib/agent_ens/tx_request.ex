defmodule AgentEns.TxRequest do
  @moduledoc """
  Unsigned request that can be handed to a wallet or signer.

  This struct is the handoff point between `ens_elixir` and the part of your
  app that actually asks for approval and sends the request.
  """

  @enforce_keys [
    :to,
    :data,
    :value,
    :chain_id,
    :description,
    :expected_signer,
    :expires_at,
    :risk_copy,
    :idempotency_key
  ]
  defstruct [
    :to,
    :data,
    :value,
    :chain_id,
    :description,
    :expected_signer,
    :expires_at,
    :risk_copy,
    :idempotency_key
  ]

  @type t :: %__MODULE__{
          to: String.t(),
          data: String.t(),
          value: String.t(),
          chain_id: non_neg_integer(),
          description: String.t(),
          expected_signer: String.t() | nil,
          expires_at: String.t(),
          risk_copy: String.t(),
          idempotency_key: String.t()
        }
end
