defmodule RegentPrivy.Session do
  @moduledoc """
  Verifies paired Privy access and identity proofs without creating a session.

  Products supply the same app ID and public verification key, then authorize and
  persist the returned evidence themselves. No cookie, token or wallet action is
  created here. A linked wallet is not required to authenticate a person.
  """

  @enforce_keys [:app_id, :privy_user_id, :session_id, :wallet_addresses]
  defstruct [
    :app_id,
    :privy_user_id,
    :session_id,
    :wallet_address,
    :wallet_addresses,
    :embedded_wallet_address,
    :user_wallet_address,
    :issued_at,
    :expires_at,
    linked_socials: []
  ]

  @type t :: %__MODULE__{
          app_id: String.t(),
          privy_user_id: String.t(),
          session_id: String.t(),
          wallet_address: String.t() | nil,
          wallet_addresses: [String.t()],
          embedded_wallet_address: String.t() | nil,
          user_wallet_address: String.t() | nil,
          issued_at: integer() | nil,
          expires_at: integer(),
          linked_socials: [RegentPrivy.linked_social()]
        }

  @doc """
  Accepts an access/identity pair and `RegentPrivy.verify_token/2` options.
  Errors contain only fixed atoms identifying the failed boundary.
  """
  @spec verify(map(), keyword()) :: {:ok, t()} | {:error, {atom(), atom()}}
  def verify(%{access: access, identity: identity}, opts)
      when is_binary(access) and is_binary(identity) do
    with :ok <- configuration(opts),
         {:ok, authenticated} <- verify_token(access, opts, :access_verification),
         {:ok, evidence} <- verify_token(identity, opts, :identity_verification),
         {:ok, sid} <- session_id(authenticated.claims),
         :ok <- bind(authenticated, evidence, sid) do
      {:ok,
       %__MODULE__{
         app_id: Keyword.fetch!(opts, :app_id),
         privy_user_id: authenticated.privy_user_id,
         session_id: sid,
         wallet_address: evidence.wallet_address,
         wallet_addresses: evidence.wallet_addresses,
         embedded_wallet_address: evidence.embedded_wallet_address,
         user_wallet_address: evidence.user_wallet_address,
         linked_socials: evidence.linked_socials,
         issued_at: evidence.claims["iat"],
         expires_at: min(authenticated.claims["exp"], evidence.claims["exp"])
       }}
    end
  end

  def verify(_pair, _opts), do: {:error, {:pair_binding, :invalid_token_pair}}

  defp configuration(opts) do
    case {opts[:app_id], opts[:verification_key]} do
      {app, key} when is_binary(app) and app != "" and is_binary(key) and key != "" -> :ok
      _ -> {:error, {:configuration, :missing_privy_config}}
    end
  end

  defp verify_token(token, opts, stage) do
    case RegentPrivy.verify_token(token, opts) do
      {:ok, evidence} -> {:ok, evidence}
      {:error, reason} -> {:error, {stage, reason}}
    end
  end

  defp session_id(%{"sid" => sid}) when is_binary(sid) do
    case String.trim(sid) do
      "" -> {:error, {:access_verification, :missing_session_id}}
      value -> {:ok, value}
    end
  end

  defp session_id(_claims), do: {:error, {:access_verification, :missing_session_id}}

  defp bind(authenticated, evidence, sid) do
    cond do
      authenticated.privy_user_id != evidence.privy_user_id ->
        {:error, {:pair_binding, :subject_mismatch}}

      not matching_session?(evidence.claims, sid) ->
        {:error, {:pair_binding, :session_mismatch}}

      Map.has_key?(authenticated.claims, "linked_accounts") ->
        {:error, {:pair_binding, :access_role_confused}}

      not is_binary(evidence.claims["linked_accounts"]) ->
        {:error, {:pair_binding, :identity_accounts_missing}}

      true ->
        :ok
    end
  end

  defp matching_session?(%{"sid" => sid}, expected) when is_binary(sid),
    do: String.trim(sid) == expected

  defp matching_session?(%{"sid" => _sid}, _expected), do: false
  defp matching_session?(_claims, _expected), do: true
end
