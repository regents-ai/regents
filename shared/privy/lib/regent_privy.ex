defmodule RegentPrivy do
  @moduledoc """
  Shared Privy identity-token verification for Regent Elixir apps.

  Verifies the ES256 signature against the app's Privy verification key and
  validates the canonical claim set: `iss` must be `privy.io`, `aud` must
  contain the app id, `exp` must be in the future, optional `nbf` must not be
  in the future, and optional `iat` may be at most 60 seconds in the future.
  Wallet addresses are extracted from the `linked_accounts` claim when
  present, normalized to trimmed lowercase `0x` hex. Every wallet entry carries
  Privy's verification time (`lv`).

  `embedded_wallet_address` is the wallet Privy made for the person (its
  `wallet_client_type` is `privy`), and `user_wallet_address` is the most
  recently verified wallet the person brought themselves. Either is nil when the
  person has no such wallet. `wallet_address`, the person's main wallet, is
  their own wallet when they have one and the Regents embedded wallet otherwise,
  so Privy making the embedded wallet during a sign-in never takes the main
  wallet from the person's own.

  Apps own their Privy configuration (app id, verification key) and pass it
  per call; this library holds no configuration or secrets.
  """

  @wallet_address_pattern ~r/\A0x[0-9a-fA-F]{40}\z/u
  @issued_at_leeway_seconds 60

  @type linked_social :: %{
          provider: :x | :github | :farcaster,
          subject: String.t(),
          username: String.t() | nil,
          display_name: String.t() | nil
        }

  @type verified :: %{
          claims: map(),
          privy_user_id: String.t(),
          wallet_address: String.t() | nil,
          wallet_addresses: [String.t()],
          embedded_wallet_address: String.t() | nil,
          user_wallet_address: String.t() | nil,
          linked_socials: [linked_social()]
        }

  @doc """
  Verifies a Privy identity token.

  Options:

    * `:app_id` — Privy app id the token audience must match (required)
    * `:verification_key` — PEM-encoded ES256 verification key (required)
    * `:now` — unix seconds used for time-claim validation (defaults to
      `System.system_time(:second)`)

  Returns `{:ok, verified}` or `{:error, reason}` where `reason` is one of
  `:invalid_verification_key`, `:token_verification_failed`,
  `:invalid_issuer`, `:invalid_audience`, `:token_expired`,
  `:token_not_yet_valid`, `:token_issued_in_future`, `:invalid_subject`,
  `:invalid_linked_accounts`, or `:invalid_token`.
  """
  @spec verify_token(String.t(), keyword()) :: {:ok, verified()} | {:error, term()}
  def verify_token(token, opts) when is_binary(token) do
    app_id = Keyword.fetch!(opts, :app_id)
    verification_key = Keyword.fetch!(opts, :verification_key)
    now = Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end)

    with {:ok, claims} <- verify_claims(token, verification_key),
         :ok <- validate_issuer(claims),
         :ok <- validate_audience(claims, app_id),
         :ok <- validate_time_claims(claims, now),
         {:ok, privy_user_id} <- fetch_subject(claims),
         {:ok, linked_accounts} <- fetch_linked_accounts(claims),
         {:ok, wallets} <- fetch_wallets(linked_accounts),
         {:ok, linked_socials} <- fetch_linked_socials(linked_accounts) do
      user_wallet = wallets |> Enum.reject(& &1.embedded?) |> signed_in_wallet()
      embedded_wallet = embedded_wallet(wallets)

      {:ok,
       %{
         claims: claims,
         privy_user_id: privy_user_id,
         wallet_address: user_wallet || embedded_wallet,
         wallet_addresses: wallets |> Enum.map(& &1.address) |> Enum.uniq(),
         embedded_wallet_address: embedded_wallet,
         user_wallet_address: user_wallet,
         linked_socials: linked_socials
       }}
    end
  rescue
    _error -> {:error, :invalid_token}
  end

  def verify_token(_token, _opts), do: {:error, :invalid_token}

  defp verify_claims(token, verification_key) do
    # JOSE reads a PEM it cannot parse as no key at all rather than raising, and
    # a signer with no key fails every token.
    case Joken.Signer.create("ES256", %{"pem" => verification_key}) do
      %Joken.Signer{jwk: %JOSE.JWK{}} = signer -> verify_signature(token, signer)
      _no_key -> {:error, :invalid_verification_key}
    end
  rescue
    _error -> {:error, :invalid_verification_key}
  end

  defp verify_signature(token, signer) do
    case Joken.verify(token, signer) do
      {:ok, claims} when is_map(claims) -> {:ok, claims}
      {:error, _reason} -> {:error, :token_verification_failed}
      _other -> {:error, :invalid_token}
    end
  end

  defp validate_issuer(%{"iss" => "privy.io"}), do: :ok
  defp validate_issuer(_claims), do: {:error, :invalid_issuer}

  defp validate_audience(%{"aud" => audience}, app_id) when is_binary(audience) do
    if audience == app_id, do: :ok, else: {:error, :invalid_audience}
  end

  defp validate_audience(%{"aud" => audiences}, app_id) when is_list(audiences) do
    if app_id in audiences, do: :ok, else: {:error, :invalid_audience}
  end

  defp validate_audience(_claims, _app_id), do: {:error, :invalid_audience}

  defp validate_time_claims(claims, now) do
    with {:ok, exp} <- fetch_integer_claim(claims, "exp"),
         :ok <- ensure_future(exp, now),
         :ok <- validate_not_before(claims, now) do
      validate_issued_at(claims, now)
    end
  end

  defp validate_not_before(claims, now) do
    case Map.fetch(claims, "nbf") do
      :error -> :ok
      {:ok, nbf} when is_integer(nbf) and nbf <= now -> :ok
      _other -> {:error, :token_not_yet_valid}
    end
  end

  defp validate_issued_at(claims, now) do
    case Map.fetch(claims, "iat") do
      :error -> :ok
      {:ok, iat} when is_integer(iat) and iat <= now + @issued_at_leeway_seconds -> :ok
      _other -> {:error, :token_issued_in_future}
    end
  end

  defp fetch_integer_claim(claims, claim_name) do
    case Map.fetch(claims, claim_name) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      _other -> {:error, :invalid_token}
    end
  end

  defp ensure_future(exp, now) when exp > now, do: :ok
  defp ensure_future(_exp, _now), do: {:error, :token_expired}

  defp fetch_subject(%{"sub" => privy_user_id})
       when is_binary(privy_user_id) and privy_user_id != "" do
    {:ok, privy_user_id}
  end

  defp fetch_subject(_claims), do: {:error, :invalid_subject}

  defp fetch_linked_accounts(%{"linked_accounts" => linked_accounts})
       when is_binary(linked_accounts) do
    with {:ok, decoded} <- Jason.decode(linked_accounts),
         true <- is_list(decoded) do
      {:ok, decoded}
    else
      _other -> {:error, :invalid_linked_accounts}
    end
  end

  defp fetch_linked_accounts(%{"linked_accounts" => _invalid}),
    do: {:error, :invalid_linked_accounts}

  defp fetch_linked_accounts(_claims), do: {:ok, []}

  defp fetch_wallets(linked_accounts),
    do: {:ok, Enum.flat_map(linked_accounts, &linked_account_wallet/1)}

  defp signed_in_wallet([]), do: nil

  defp signed_in_wallet(wallets), do: Enum.max_by(wallets, & &1.verified_at).address

  defp embedded_wallet(wallets) do
    case Enum.find(wallets, & &1.embedded?) do
      nil -> nil
      wallet -> wallet.address
    end
  end

  defp fetch_linked_socials(linked_accounts) do
    {:ok, Enum.flat_map(linked_accounts, &linked_account_social/1)}
  end

  defp linked_account_social(%{"type" => "twitter_oauth"} = linked_account) do
    with {:ok, subject} <- required_string(linked_account, "subject"),
         {:ok, username} <- optional_string(linked_account, "username"),
         {:ok, display_name} <- optional_string(linked_account, "name") do
      [
        %{
          provider: :x,
          subject: subject,
          username: username,
          display_name: display_name
        }
      ]
    else
      _other -> []
    end
  end

  defp linked_account_social(%{"type" => "github_oauth"} = linked_account) do
    with {:ok, subject} <- required_string(linked_account, "subject"),
         {:ok, username} <- optional_string(linked_account, "username") do
      [
        %{
          provider: :github,
          subject: subject,
          username: username,
          display_name: nil
        }
      ]
    else
      _other -> []
    end
  end

  defp linked_account_social(%{"type" => "farcaster", "fid" => fid} = linked_account)
       when is_integer(fid) and fid > 0 do
    with {:ok, username} <- optional_string(linked_account, "username") do
      [
        %{
          provider: :farcaster,
          subject: Integer.to_string(fid),
          username: username,
          display_name: nil
        }
      ]
    else
      _other -> []
    end
  end

  defp linked_account_social(_linked_account), do: []

  defp required_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _other -> :error
    end
  end

  defp optional_string(map, key) do
    case Map.fetch(map, key) do
      :error -> {:ok, nil}
      {:ok, nil} -> {:ok, nil}
      {:ok, value} when is_binary(value) -> {:ok, value}
      _other -> :error
    end
  end

  defp linked_account_wallet(
         %{"type" => "wallet", "address" => address, "lv" => verified_at} = account
       )
       when is_binary(address) and is_integer(verified_at) and verified_at > 0 do
    with "ethereum" <- Map.get(account, "chain_type", "ethereum"),
         normalized when is_binary(normalized) <- normalize_wallet_address(address) do
      [
        %{
          address: normalized,
          verified_at: verified_at,
          embedded?: Map.get(account, "wallet_client_type") == "privy"
        }
      ]
    else
      _other -> []
    end
  end

  defp linked_account_wallet(_linked_account), do: []

  defp normalize_wallet_address(value) when is_binary(value) do
    trimmed = String.trim(value)

    if String.match?(trimmed, @wallet_address_pattern) do
      String.downcase(trimmed)
    else
      nil
    end
  end
end
