defmodule AshPlatform.TestPrivyVerifier do
  @moduledoc false

  @identity_suffix "-identity"

  @doc """
  The identity token deterministically paired with `access_token`.

  Real Privy access and identity tokens are distinct strings with distinct
  roles, so the fixtures are too. `test/browser/support/authenticated_privy.ts`
  builds the same partner for the acceptance browsers and has to stay in step
  with this.
  """
  def identity_token(access_token), do: access_token <> @identity_suffix

  @doc """
  The session exchange the controller performs, in place of
  `RegentPrivy.Session.verify/2`.

  Only an access token names a session and only its own partner is that
  session's signed evidence, so a swapped, reused or unpaired token is no pair
  at all and never reaches the session boundary. Refusals carry the same tagged
  classification `RegentPrivy.Session.verify/2` returns.
  """
  def verify(%{access: access, identity: identity}, opts)
      when is_binary(access) and is_binary(identity) do
    access |> access_evidence() |> paired(identity == identity_token(access), opts)
  end

  defp paired({:ok, evidence}, true, opts),
    do: {:ok, struct!(RegentPrivy.Session, Map.put(evidence, :app_id, opts[:app_id]))}

  defp paired({:ok, _evidence}, false, _opts), do: {:error, {:pair_binding, :session_mismatch}}
  defp paired({:error, reason}, _matched, _opts), do: {:error, {:access_verification, reason}}

  defp access_evidence("valid") do
    {:ok,
     %{
       session_id: "browser-session",
       privy_user_id: "did:privy:verified",
       wallet_address: "0x1111111111111111111111111111111111111111",
       wallet_addresses: ["0x1111111111111111111111111111111111111111"]
     }}
  end

  defp access_evidence("no-wallet") do
    {:ok,
     %{
       session_id: "browser-session",
       privy_user_id: "did:privy:verified",
       wallet_address: nil,
       wallet_addresses: []
     }}
  end

  defp access_evidence("changed-wallet") do
    {:ok,
     %{
       session_id: "browser-session",
       privy_user_id: "did:privy:verified",
       wallet_address: "0x2222222222222222222222222222222222222222",
       wallet_addresses: ["0x2222222222222222222222222222222222222222"]
     }}
  end

  defp access_evidence("other-account") do
    {:ok,
     %{
       session_id: "other-browser-session",
       privy_user_id: "did:privy:other",
       wallet_address: "0x3333333333333333333333333333333333333333",
       wallet_addresses: ["0x3333333333333333333333333333333333333333"]
     }}
  end

  defp access_evidence("valid-staking") do
    {:ok,
     %{
       session_id: "staking-browser-session",
       privy_user_id: "did:privy:staking-browser",
       wallet_address: "0x1111111111111111111111111111111111111111",
       wallet_addresses: ["0x1111111111111111111111111111111111111111"]
     }}
  end

  defp access_evidence("valid-redemption") do
    {:ok,
     %{
       session_id: "redemption-browser-session",
       privy_user_id: "did:privy:redemption-browser",
       wallet_address: "0x1111111111111111111111111111111111111111",
       wallet_addresses: ["0x1111111111111111111111111111111111111111"]
     }}
  end

  defp access_evidence("valid-regents-club") do
    {:ok,
     %{
       session_id: "regents-club-browser-session",
       privy_user_id: "did:privy:regents-club-owner",
       wallet_address: "0x45C9a201e2937608905fEF17De9A67f25F9f98E0",
       wallet_addresses: ["0x45C9a201e2937608905fEF17De9A67f25F9f98E0"]
     }}
  end

  defp access_evidence("valid-formation-cloud") do
    {:ok,
     %{
       session_id: "formation-cloud-browser-session",
       privy_user_id: "did:privy:formation-cloud-browser",
       wallet_address: "0x4444444444444444444444444444444444444444",
       wallet_addresses: ["0x4444444444444444444444444444444444444444"]
     }}
  end

  defp access_evidence("conflicting-social") do
    {:ok,
     %{
       session_id: "conflicting-social-session",
       privy_user_id: "did:privy:conflicting-social",
       wallet_address: "0x5555555555555555555555555555555555555555",
       wallet_addresses: ["0x5555555555555555555555555555555555555555"],
       linked_socials: [
         %{
           provider: :x,
           subject: "shared-x-subject",
           username: "other",
           display_name: nil
         }
       ]
     }}
  end

  # The access token is well-formed for this app but its own verification is
  # refused, which is the one refusal a fresh provider login can clear. The
  # catch-all below is the generic refusal, so both live in the same stage.
  defp access_evidence("stale-access"), do: {:error, :token_verification_failed}

  defp access_evidence(_token), do: {:error, :invalid_token}
end
