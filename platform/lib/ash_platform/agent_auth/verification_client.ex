defmodule AshPlatform.AgentAuth.VerificationClient do
  @moduledoc false

  @type envelope :: %{
          required(:method) => String.t(),
          required(:path) => String.t(),
          required(:headers) => %{String.t() => String.t()},
          required(:body) => String.t() | nil
        }

  @type verified_identity :: %{
          required(:agent_id) => String.t(),
          required(:registry_address) => String.t(),
          required(:token_id) => String.t(),
          required(:wallet) => String.t()
        }

  @callback verify(envelope()) :: {:ok, verified_identity()} | {:error, atom()}

  def verify(envelope) do
    Application.fetch_env!(:ash_platform, :agent_verification_client).verify(envelope)
  end
end
