defmodule AshPlatform.PrivyTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Privy

  @wallet "0x1111111111111111111111111111111111111111"
  @social %{
    provider: :github,
    subject: "github-user-7",
    username: "regents-ai",
    display_name: nil
  }

  # The real provider's roles: an access token authenticates the subject and
  # session and carries no linked accounts, while its identity token repeats
  # that subject and session and carries the signed accounts as a JSON string.
  defmodule SharedVerifierStub do
    @wallet "0x1111111111111111111111111111111111111111"

    @linked_accounts Jason.encode!([
                       %{"type" => "wallet", "address" => @wallet},
                       %{
                         "type" => "github_oauth",
                         "subject" => "github-user-7",
                         "username" => "regents-ai"
                       }
                     ])

    def verify_token(token, _opts), do: verified(token)

    defp verified("access"), do: session(%{"sub" => "did:privy:test", "sid" => "session"})

    defp verified("identity"),
      do:
        session(%{
          "sub" => "did:privy:test",
          "sid" => "session",
          "linked_accounts" => @linked_accounts
        })

    defp verified("identity-without-wallets"),
      do:
        session(%{
          "sub" => "did:privy:test",
          "sid" => "session",
          "linked_accounts" => Jason.encode!([])
        })

    defp verified("access-other-subject"),
      do: session(%{"sub" => "did:privy:other", "sid" => "session"})

    defp verified("identity-other-subject"),
      do:
        session(%{
          "sub" => "did:privy:other",
          "sid" => "session",
          "linked_accounts" => @linked_accounts
        })

    defp verified("access-other-session"),
      do: session(%{"sub" => "did:privy:test", "sid" => "other-session"})

    defp verified("access-blank-sid"),
      do: session(%{"sub" => "did:privy:test", "sid" => "   "})

    defp verified("identity-without-sid"),
      do: session(%{"sub" => "did:privy:test", "linked_accounts" => @linked_accounts})

    # The shared verifier refuses a `linked_accounts` string that does not
    # decode to a list before it ever returns claims.
    defp verified("identity-malformed-accounts"), do: {:error, :invalid_linked_accounts}

    defp verified("expired"), do: {:error, :token_expired}
    defp verified("wrong-app"), do: {:error, :invalid_audience}
    defp verified("wrong-issuer"), do: {:error, :invalid_issuer}
    defp verified("forged"), do: {:error, :token_verification_failed}
    defp verified(_malformed), do: {:error, :invalid_token}

    defp session(claims) do
      {:ok,
       %{
         claims: claims,
         privy_user_id: claims["sub"],
         wallet_address: wallet_address(claims),
         wallet_addresses: wallet_addresses(claims),
         linked_socials: linked_socials(claims)
       }}
    end

    defp wallet_address(claims), do: claims |> wallet_addresses() |> List.first()

    defp wallet_addresses(%{"linked_accounts" => @linked_accounts}), do: [@wallet]
    defp wallet_addresses(_claims), do: []

    defp linked_socials(%{"linked_accounts" => @linked_accounts}),
      do: [
        %{
          provider: :github,
          subject: "github-user-7",
          username: "regents-ai",
          display_name: nil
        }
      ]

    defp linked_socials(_claims), do: []
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

  test "SIGNED_EVIDENCE_ONLY: a matching pair yields the identity token's evidence" do
    assert {:ok,
            %AshPlatform.VerifiedPrivyIdentity{
              privy_user_id: "did:privy:test",
              session_id: "session",
              wallet_address: @wallet,
              wallet_addresses: [@wallet],
              linked_socials: [@social]
            }} = pair("access", "identity")
  end

  test "SIGNED_EVIDENCE_ONLY: identity evidence with no wallets still reaches the boundary" do
    assert {:ok,
            %AshPlatform.VerifiedPrivyIdentity{
              privy_user_id: "did:privy:test",
              session_id: "session",
              wallet_address: nil,
              wallet_addresses: [],
              linked_socials: []
            }} = pair("access", "identity-without-wallets")
  end

  test "MUTUALLY_EXCLUSIVE_TOKEN_ROLES: each slot accepts only its own token role" do
    # An access token carries no signed accounts, so it is never evidence, and
    # an identity token never authenticates a session on its own.
    assert pair("access", "access") == {:error, :invalid_session_pair}
    assert pair("identity", "access") == {:error, :invalid_session_pair}

    # The same identity token in both slots is refused by the access slot.
    assert pair("identity", "identity") == {:error, :invalid_session_pair}
  end

  test "INDEPENDENT_VERIFICATION_AND_BINDING: evidence binds only to the authenticated session" do
    assert pair("access", "identity-other-subject") == {:error, :invalid_session_pair}
    assert pair("access-other-subject", "identity") == {:error, :invalid_session_pair}
    assert pair("access-other-session", "identity") == {:error, :invalid_session_pair}
    assert pair("access", "identity-without-sid") == {:error, :invalid_session_pair}
    assert pair("access-blank-sid", "identity") == {:error, :invalid_session_pair}
  end

  test "INDEPENDENT_VERIFICATION_AND_BINDING: either slot's own verification failure refuses the pair" do
    for unverifiable <- ~w(forged expired wrong-app wrong-issuer malformed) do
      assert {:error, _refused} = pair(unverifiable, "identity")
      assert {:error, _refused} = pair("access", unverifiable)
    end
  end

  test "MUTUALLY_EXCLUSIVE_TOKEN_ROLES: malformed signed accounts are not evidence" do
    assert {:error, :invalid_linked_accounts} = pair("access", "identity-malformed-accounts")
  end

  test "FAIL_CLOSED: a pair that is not two strings is refused before the provider is asked" do
    assert Privy.verify_session_pair(%{access: "access", identity: nil}) ==
             {:error, :invalid_session_pair}

    assert Privy.verify_session_pair(%{access: nil, identity: "identity"}) ==
             {:error, :invalid_session_pair}

    assert Privy.verify_session_pair(%{}) == {:error, :invalid_session_pair}
  end

  test "FAIL_CLOSED: an unconfigured verification key refuses every pair" do
    Application.delete_env(:ash_platform, :privy)

    assert pair("access", "identity") == {:error, :missing_privy_config}
  end

  defp pair(access, identity),
    do: Privy.verify_session_pair(%{access: access, identity: identity})

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
