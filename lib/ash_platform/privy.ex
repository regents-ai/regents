defmodule AshPlatform.Privy do
  @moduledoc false

  @callback verify_access_token(String.t()) ::
              {:ok, AshPlatform.VerifiedPrivyIdentity.t()} | {:error, term()}

  alias AshPlatform.VerifiedPrivyIdentity

  def verify_access_token(token) when is_binary(token) do
    with {:ok, opts} <- verification_options(),
         {:ok, verified} <- verifier().verify_token(token, opts),
         {:ok, session_id} <- session_id(verified.claims) do
      {:ok,
       %VerifiedPrivyIdentity{
         privy_user_id: verified.privy_user_id,
         session_id: session_id,
         wallet_address: verified.wallet_address,
         wallet_addresses: verified.wallet_addresses
       }}
    end
  end

  def verify_access_token(_token), do: {:error, :invalid_access_token}

  defp verifier, do: Application.get_env(:ash_platform, :regent_privy_module, RegentPrivy)

  defp verification_options do
    config = Application.get_env(:ash_platform, :privy, [])

    case {config[:app_id], config[:verification_key]} do
      {app_id, key} when is_binary(app_id) and app_id != "" and is_binary(key) and key != "" ->
        clock = config[:clock] || fn -> System.system_time(:second) end
        {:ok, [app_id: app_id, verification_key: key, now: clock.()]}

      _ ->
        {:error, :missing_privy_config}
    end
  end

  defp session_id(%{"sid" => sid}) when is_binary(sid) and sid != "" do
    case String.trim(sid) do
      "" -> {:error, :invalid_access_token}
      session_id -> {:ok, session_id}
    end
  end

  defp session_id(_claims), do: {:error, :invalid_access_token}
end
