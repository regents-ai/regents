defmodule AshPlatform.TestPrivyVerifier do
  def verify_access_token("valid") do
    {:ok,
     %AshPlatform.VerifiedPrivyIdentity{
       session_id: "browser-session",
       privy_user_id: "did:privy:verified",
       wallet_address: "0x1111111111111111111111111111111111111111",
       wallet_addresses: ["0x1111111111111111111111111111111111111111"]
     }}
  end

  def verify_access_token("no-wallet") do
    {:ok,
     %AshPlatform.VerifiedPrivyIdentity{
       session_id: "browser-session",
       privy_user_id: "did:privy:verified",
       wallet_address: nil,
       wallet_addresses: []
     }}
  end

  def verify_access_token("valid-staking") do
    {:ok,
     %AshPlatform.VerifiedPrivyIdentity{
       session_id: "staking-browser-session",
       privy_user_id: "did:privy:staking-browser",
       wallet_address: "0x1111111111111111111111111111111111111111",
       wallet_addresses: ["0x1111111111111111111111111111111111111111"]
     }}
  end

  def verify_access_token("valid-redemption") do
    {:ok,
     %AshPlatform.VerifiedPrivyIdentity{
       session_id: "redemption-browser-session",
       privy_user_id: "did:privy:redemption-browser",
       wallet_address: "0x1111111111111111111111111111111111111111",
       wallet_addresses: ["0x1111111111111111111111111111111111111111"]
     }}
  end

  def verify_access_token("valid-autolaunch-draft") do
    {:ok,
     %AshPlatform.VerifiedPrivyIdentity{
       session_id: "autolaunch-draft-browser-session",
       privy_user_id: "did:privy:autolaunch-draft-browser",
       wallet_address: "0x3333333333333333333333333333333333333333",
       wallet_addresses: ["0x3333333333333333333333333333333333333333"]
     }}
  end

  def verify_access_token("valid-formation-cloud") do
    {:ok,
     %AshPlatform.VerifiedPrivyIdentity{
       session_id: "formation-cloud-browser-session",
       privy_user_id: "did:privy:formation-cloud-browser",
       wallet_address: "0x4444444444444444444444444444444444444444",
       wallet_addresses: ["0x4444444444444444444444444444444444444444"]
     }}
  end

  def verify_access_token("identity-token"), do: {:error, :invalid_access_token}
  def verify_access_token("missing-sid"), do: {:error, :invalid_access_token}
  def verify_access_token(_token), do: {:error, :invalid_token}
end
