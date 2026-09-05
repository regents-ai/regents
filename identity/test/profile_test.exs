defmodule RegentIdentity.ProfileTest do
  use ExUnit.Case, async: false
  alias RegentIdentity, as: Identity
  @wallet "0x1111111111111111111111111111111111111111"
  @other_wallet "0x2222222222222222222222222222222222222222"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentIdentity.TestRepo)
    %{actor: actor("person-#{System.unique_integer([:positive])}")}
  end

  defp actor(subject, attrs \\ %{}) do
    struct!(
      RegentPrivy.Session,
      Map.merge(
        %{
          app_id: "common-app",
          privy_user_id: subject,
          session_id: "local-session",
          wallet_addresses: [@wallet],
          wallet_address: @wallet,
          issued_at: System.system_time(:second) - 10,
          expires_at: System.system_time(:second) + 3600
        },
        attrs
      )
    )
  end

  test "same verified subject resolves the same ID and identical rerun makes no change", %{
    actor: actor
  } do
    assert {:ok, first} = Identity.sync(actor)
    assert {:ok, second} = Identity.sync(%{actor | session_id: "another-site-session"})
    assert first.id == second.id
    assert first.updated_at == second.updated_at
    assert {:ok, found} = Identity.get_my_profile(actor: actor)
    assert found.id == first.id
    assert {:ok, nil} = Identity.get_my_profile(actor: %{actor | privy_user_id: "other"})
    assert {:error, _} = Identity.get_my_profile()
  end

  test "X proof is private and immutable subject owns mutable handle", %{actor: actor} do
    x = %{provider: :x, subject: "x-123", username: "old", display_name: "Name"}
    actor = %{actor | linked_socials: [x], wallet_addresses: [], wallet_address: nil}
    assert {:ok, profile} = Identity.sync(actor)
    assert Identity.present(profile).wallet == %{address: nil, verified: false}

    assert Identity.present(profile).x == %{
             username: "old",
             display_name: "Name",
             verified: true,
             source: "privy"
           }

    refute Map.has_key?(Identity.present(profile), :privy_user_id)
    refute Map.has_key?(Identity.present(profile).x, :subject)
    assert {:error, _} = Identity.sync(%{actor | privy_user_id: "intruder"})

    assert {:ok, updated} =
             Identity.sync(%{
               actor
               | issued_at: actor.issued_at + 1,
                 linked_socials: [%{x | username: "new"}]
             })

    assert updated.id == profile.id
    assert updated.x_subject == "x-123"
    assert Identity.present(updated).x.username == "new"
  end

  test "wallet choice survives linked-account ordering and becomes unverified after unlink", %{
    actor: actor
  } do
    assert {:ok, profile} = Identity.sync(actor)
    proof = %{actor | issued_at: actor.issued_at + 1, wallet_addresses: [@other_wallet, @wallet]}
    assert {:ok, refreshed} = Identity.sync(proof)
    assert refreshed.wallet_address == @wallet

    assert {:ok, selected} =
             Identity.edit_profile(refreshed, %{wallet_address: @other_wallet}, actor: proof)

    assert selected.wallet_address == @other_wallet

    assert {:error, _} =
             Identity.edit_profile(
               selected,
               %{wallet_address: "0x3333333333333333333333333333333333333333"},
               actor: proof
             )

    assert {:ok, unlinked} =
             Identity.sync(%{proof | issued_at: proof.issued_at + 1, wallet_addresses: [@wallet]})

    assert Identity.present(unlinked).wallet == %{address: @other_wallet, verified: false}
    assert profile.id == unlinked.id
  end

  test "owner checks apply to edits even with a valid different actor", %{actor: actor} do
    assert {:ok, profile} = Identity.sync(actor)

    assert {:error, _} =
             Identity.edit_profile(profile, %{display_name: "Taken"},
               actor: %{actor | privy_user_id: "other"}
             )

    assert {:ok, own} = Identity.edit_profile(profile, %{display_name: "Mine"}, actor: actor)
    assert own.display_name == "Mine"
  end

  test "stale and conflicting snapshots cannot restore removed links", %{actor: actor} do
    assert {:ok, _} = Identity.sync(actor)

    assert {:error, _} =
             Identity.sync(%{actor | wallet_addresses: []})

    newer = %{actor | issued_at: actor.issued_at + 2}
    assert {:ok, _} = Identity.sync(newer)

    assert {:error, _} =
             Identity.sync(%{actor | issued_at: actor.issued_at + 1, wallet_addresses: []})

    assert {:error, :unverified_identity} = Identity.sync(%{actor | expires_at: 0})
    assert {:ok, retained} = Identity.get_my_profile(actor: newer)
    assert retained.wallet_addresses == [@wallet]
    assert retained.proof_issued_at == newer.issued_at
  end

  test "different application subjects are never merged", %{actor: actor} do
    assert {:ok, first} = Identity.sync(actor)
    assert {:ok, second} = Identity.sync(%{actor | app_id: "legacy-other-app"})
    refute first.id == second.id
  end

  test "direct Ash refresh and stale record edits cannot bypass newer evidence", %{actor: actor} do
    assert {:ok, original} = Identity.sync(actor)

    assert {:ok, _} =
             Identity.sync(%{actor | issued_at: actor.issued_at + 2, wallet_addresses: []})

    assert {:error, _} =
             original |> Ash.Changeset.for_update(:refresh, %{}, actor: actor) |> Ash.update()

    assert {:ok, cleared} = Identity.edit_profile(original, %{wallet_address: nil}, actor: actor)
    assert {:error, _} = Identity.edit_profile(cleared, %{wallet_address: @wallet}, actor: actor)
    assert {:ok, retained} = Identity.get_my_profile(actor: actor)
    assert retained.wallet_addresses == []
    assert retained.wallet_address == nil
  end

  test "display names are bounded in bytes as well as visible characters", %{actor: actor} do
    assert {:ok, profile} = Identity.sync(actor)

    assert {:error, _} =
             Identity.edit_profile(
               profile,
               %{display_name: "a" <> String.duplicate(<<0xCC, 0x81>>, 200)},
               actor: actor
             )
  end

  test "a direct refresh from an old record applies every field of newer proof", %{actor: actor} do
    assert {:ok, original} = Identity.sync(actor)
    x = %{provider: :x, subject: "x-new", username: "new", display_name: nil}

    assert {:ok, _} =
             Identity.sync(%{
               actor
               | issued_at: actor.issued_at + 1,
                 wallet_addresses: [@other_wallet],
                 linked_socials: [x]
             })

    latest = %{actor | issued_at: actor.issued_at + 2}

    assert {:ok, _} =
             original |> Ash.Changeset.for_update(:refresh, %{}, actor: latest) |> Ash.update()

    assert {:ok, stored} = Identity.get_my_profile(actor: latest)
    assert stored.wallet_addresses == [@wallet]
    assert stored.x_subject == nil
    assert stored.proof_issued_at == latest.issued_at
  end
end
