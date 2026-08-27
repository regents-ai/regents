defmodule AshPlatform.Privy do
  @moduledoc false

  @type session_pair :: %{access: String.t(), identity: String.t()}

  @callback verify_session_pair(session_pair()) ::
              {:ok, AshPlatform.VerifiedPrivyIdentity.t()} | {:error, term()}

  alias AshPlatform.VerifiedPrivyIdentity

  @doc """
  Exchanges a Privy token pair for the signed identity evidence it proves.

  The access token authenticates the session and the identity token carries the
  signed linked accounts. Each is verified independently against the same
  public key, so ordinary signed-token expiry is the whole freshness authority
  and no evidence is accepted for a subject or session the access token did not
  itself authenticate.
  """
  def verify_session_pair(%{access: access, identity: identity})
      when is_binary(access) and is_binary(identity) do
    with {:ok, opts} <- verification_options(),
         {:ok, authenticated} <- verify(access, opts),
         {:ok, evidence} <- verify(identity, opts) do
      bind(authenticated, evidence)
    end
  end

  def verify_session_pair(_pair), do: {:error, :invalid_session_pair}

  defp verify(token, opts) do
    with {:ok, verified} <- verifier().verify_token(token, opts),
         {:ok, session_id} <- session_id(verified.claims) do
      {:ok, Map.put(verified, :session_id, session_id)}
    end
  end

  # Privy's two token roles are disjoint, and the raw claim is what separates
  # them: only an identity token carries `linked_accounts`, and the shared
  # verifier has already refused one that does not decode to a list. A decoded
  # empty list is well formed, so evidence with no wallets still binds and the
  # authority below it can invalidate the wallets it supersedes.
  defp bind(
         %{claims: authentication, privy_user_id: did, session_id: sid},
         %{claims: %{"linked_accounts" => accounts}, privy_user_id: did, session_id: sid} =
           evidence
       )
       when is_binary(accounts) and not is_map_key(authentication, "linked_accounts") do
    {:ok,
     %VerifiedPrivyIdentity{
       privy_user_id: did,
       session_id: sid,
       wallet_address: evidence.wallet_address,
       wallet_addresses: evidence.wallet_addresses,
       linked_socials: evidence.linked_socials
     }}
  end

  defp bind(_authenticated, _evidence), do: {:error, :invalid_session_pair}

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
      "" -> {:error, :invalid_session_pair}
      session_id -> {:ok, session_id}
    end
  end

  defp session_id(_claims), do: {:error, :invalid_session_pair}
end
