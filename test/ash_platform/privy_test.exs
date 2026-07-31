defmodule AshPlatform.PrivyTest do
  use ExUnit.Case, async: false

  defmodule SharedVerifierStub do
    def verify_token(token, _opts) do
      claims =
        case token do
          "access" -> %{"sid" => "session"}
          "empty-sid" -> %{"sid" => "  "}
          "identity" -> %{}
        end

      {:ok,
       %{
         claims: claims,
         privy_user_id: "did:privy:test",
         wallet_address: nil,
         wallet_addresses: [],
         linked_socials: [
           %{
             provider: :github,
             subject: "github-user-7",
             username: "regents-ai",
             display_name: nil
           }
         ]
       }}
    end
  end

  setup do
    old_privy = Application.get_env(:ash_platform, :privy)
    old_verifier = Application.get_env(:ash_platform, :regent_privy_module)
    Application.put_env(:ash_platform, :privy, app_id: "app", verification_key: "key")
    Application.put_env(:ash_platform, :regent_privy_module, SharedVerifierStub)

    on_exit(fn ->
      restore(:privy, old_privy)
      restore(:regent_privy_module, old_verifier)
    end)
  end

  test "requires a nonempty access-token session claim" do
    assert {:ok,
            %AshPlatform.VerifiedPrivyIdentity{
              privy_user_id: "did:privy:test",
              session_id: "session",
              wallet_address: nil,
              wallet_addresses: [],
              linked_socials: [
                %{
                  provider: :github,
                  subject: "github-user-7",
                  username: "regents-ai",
                  display_name: nil
                }
              ]
            }} = AshPlatform.Privy.verify_access_token("access")

    assert {:error, :invalid_access_token} = AshPlatform.Privy.verify_access_token("identity")
    assert {:error, :invalid_access_token} = AshPlatform.Privy.verify_access_token("empty-sid")
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
