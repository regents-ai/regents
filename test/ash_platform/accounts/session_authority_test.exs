defmodule AshPlatform.Accounts.SessionAuthorityTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.Repo

  @tombstone_generation 9_223_372_036_854_775_807

  setup do
    {:ok, first: account("first"), second: account("second")}
  end

  test "a lineage is only a lookup key until a server row binds it", %{first: first} do
    lineage = SessionAuthority.mint_lineage()

    assert SessionAuthority.capture(lineage, first.id) == nil
    assert {:ok, %{generation: 0}} = bind(lineage, first.id)
    assert %{lineage: ^lineage, generation: 0} = SessionAuthority.capture(lineage, first.id)
  end

  test "authority never answers for an account it is not bound to", %{
    first: first,
    second: second
  } do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, _authority} = bind(lineage, first.id)

    assert SessionAuthority.capture(lineage, second.id) == nil
    assert SessionAuthority.capture(SessionAuthority.mint_lineage(), first.id) == nil
  end

  test "the raw lineage is redacted from inspection", %{first: first} do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, authority} = bind(lineage, first.id)

    refute inspect(authority) =~ lineage
    refute inspect(authority) =~ "lineage"
  end

  test "a verified same-account refresh preserves the lineage and its generation", %{
    first: first
  } do
    lineage = SessionAuthority.mint_lineage()

    assert {:ok, %{generation: 0}} = bind(lineage, first.id)
    assert {:ok, %{lineage: ^lineage, generation: 0}} = bind(lineage, first.id)
    assert {:ok, %{lineage: ^lineage, generation: 0}} = bind(lineage, first.id)
  end

  test "a verified account switch advances the generation and rebinds one lineage", %{
    first: first,
    second: second
  } do
    lineage = SessionAuthority.mint_lineage()

    assert {:ok, %{generation: 0, human_account_id: first_id}} = bind(lineage, first.id)
    assert first_id == first.id

    assert {:ok, %{lineage: ^lineage, generation: 1, human_account_id: second_id}} =
             bind(lineage, second.id)

    assert second_id == second.id
    assert SessionAuthority.capture(lineage, first.id) == nil
    assert %{generation: 1} = SessionAuthority.capture(lineage, second.id)
    assert authority_count(lineage) == 1
  end

  test "a switch at the reserved generation boundary fails closed without wrapping", %{
    first: first,
    second: second
  } do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, _authority} = bind(lineage, first.id)
    force_generation(lineage, @tombstone_generation - 1)

    assert {:error, :session_generation_exhausted} = bind(lineage, second.id)

    boundary = @tombstone_generation - 1

    assert %{generation: ^boundary, human_account_id: bound, revoked_at: nil} =
             SessionAuthority.capture(lineage, first.id)

    assert bound == first.id
    assert SessionAuthority.capture(lineage, second.id) == nil
  end

  test "sign-in established before a revoke cannot survive the revoke", %{first: first} do
    lineage = SessionAuthority.mint_lineage()

    assert {:ok, %{generation: 0}} = bind(lineage, first.id)
    assert {:ok, %{generation: @tombstone_generation}} = SessionAuthority.revoke(lineage)

    assert SessionAuthority.capture(lineage, first.id) == nil
    assert {:error, :session_revoked} = bind(lineage, first.id)
  end

  test "a revoke that tombstones first refuses the sign-in released behind it", %{first: first} do
    lineage = SessionAuthority.mint_lineage()

    assert {:ok, %{generation: @tombstone_generation, human_account_id: nil}} =
             SessionAuthority.revoke(lineage)

    assert {:error, :session_revoked} = bind(lineage, first.id)
    assert SessionAuthority.capture(lineage, first.id) == nil
    assert authority_count(lineage) == 1
  end

  test "revocation is keyed by lineage alone and repeats as an exact no-op", %{
    first: first,
    second: second
  } do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, _authority} = bind(lineage, first.id)
    assert {:ok, _switched} = bind(lineage, second.id)

    assert {:ok, revoked} = SessionAuthority.revoke(lineage)
    assert revoked.generation == @tombstone_generation
    assert revoked.human_account_id == second.id

    for _repeat <- 1..3 do
      assert {:ok, repeated} = SessionAuthority.revoke(lineage)
      assert repeated.revoked_at == revoked.revoked_at
      assert repeated.updated_at == revoked.updated_at
      assert repeated.generation == @tombstone_generation
    end

    assert authority_count(lineage) == 1
  end

  test "a revoked tombstone is retained rather than deleted", %{first: first} do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, _authority} = bind(lineage, first.id)
    assert {:ok, _revoked} = SessionAuthority.revoke(lineage)

    assert %{"revoked_at" => revoked_at, "generation" => @tombstone_generation} =
             authority_row(lineage)

    refute is_nil(revoked_at)
  end

  test "an anonymous session has no lineage to revoke" do
    assert {:ok, nil} = SessionAuthority.revoke(nil)
  end

  test "a protected write runs only while its capture is still current", %{first: first} do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, capture} = bind(lineage, first.id)

    assert {:ok, :written} =
             SessionAuthority.authorize(capture, fn _current -> {:ok, :written} end)

    assert {:ok, _revoked} = SessionAuthority.revoke(lineage)

    assert {:error, :session_revoked} =
             SessionAuthority.authorize(capture, fn _current -> flunk("write escaped") end)
  end

  test "a capture superseded by an account switch can no longer write", %{
    first: first,
    second: second
  } do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, capture} = bind(lineage, first.id)
    assert {:ok, _switched} = bind(lineage, second.id)

    assert {:error, :session_revoked} =
             SessionAuthority.authorize(capture, fn _current -> flunk("write escaped") end)
  end

  test "an absent capture can never authorize a write" do
    assert {:error, :session_revoked} =
             SessionAuthority.authorize(nil, fn _current -> flunk("write escaped") end)
  end

  test "a failed protected write removes the authority it attempted", %{first: first} do
    lineage = SessionAuthority.mint_lineage()

    assert {:error, :evidence_rejected} =
             SessionAuthority.bind(lineage, first.id, fn _authority ->
               {:error, :evidence_rejected}
             end)

    assert authority_row(lineage) == nil
    assert SessionAuthority.capture(lineage, first.id) == nil
  end

  test "a raising protected write removes the authority it attempted", %{first: first} do
    lineage = SessionAuthority.mint_lineage()

    assert_raise RuntimeError, "evidence exploded", fn ->
      SessionAuthority.bind(lineage, first.id, fn _authority -> raise "evidence exploded" end)
    end

    assert authority_row(lineage) == nil
  end

  test "an outer rollback removes the authority an inner bind established", %{first: first} do
    lineage = SessionAuthority.mint_lineage()

    assert {:error, :outer_failure} =
             Repo.transaction(fn ->
               assert {:ok, _authority} = bind(lineage, first.id)
               Repo.rollback(:outer_failure)
             end)

    assert authority_row(lineage) == nil
  end

  test "a rolled back switch leaves the prior binding and generation intact", %{
    first: first,
    second: second
  } do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, _authority} = bind(lineage, first.id)

    assert {:error, :switch_rejected} =
             SessionAuthority.bind(lineage, second.id, fn _authority ->
               {:error, :switch_rejected}
             end)

    assert %{generation: 0, human_account_id: bound} = SessionAuthority.capture(lineage, first.id)
    assert bound == first.id
    assert authority_count(lineage) == 1
  end

  test "the database refuses to delete an account that still holds authority", %{first: first} do
    lineage = SessionAuthority.mint_lineage()
    assert {:ok, _authority} = bind(lineage, first.id)

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             Repo.query(
               "DELETE FROM platform.platform_human_users WHERE id = $1",
               [first.id]
             )
  end

  test "the database refuses a negative generation" do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_authority(SessionAuthority.mint_lineage(), nil, -1, nil)
  end

  test "the database reserves the maximum generation for terminal tombstones", %{first: first} do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_authority(
               SessionAuthority.mint_lineage(),
               first.id,
               @tombstone_generation,
               nil
             )

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_authority(SessionAuthority.mint_lineage(), first.id, 7, DateTime.utc_now())

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_authority(SessionAuthority.mint_lineage(), nil, 0, nil)
  end

  defp bind(lineage, human_account_id) do
    SessionAuthority.bind(lineage, human_account_id, &{:ok, &1})
  end

  defp account(suffix) do
    wallet = "0x" <> String.pad_leading(Integer.to_string(unique()), 40, "0")

    Accounts.register_verified!(
      "did:privy:session-authority:#{suffix}:#{unique()}",
      wallet,
      [wallet],
      actor: %System{}
    )
  end

  defp unique, do: Elixir.System.unique_integer([:positive])

  defp authority_row(lineage) do
    {:ok, %{columns: columns, rows: rows}} =
      Repo.query(
        "SELECT lineage, human_account_id, generation, revoked_at FROM session_authorities WHERE lineage = $1",
        [Ecto.UUID.dump!(lineage)]
      )

    case rows do
      [row] -> columns |> Enum.zip(row) |> Map.new()
      [] -> nil
    end
  end

  defp authority_count(lineage) do
    {:ok, %{rows: [[count]]}} =
      Repo.query("SELECT count(*) FROM session_authorities WHERE lineage = $1", [
        Ecto.UUID.dump!(lineage)
      ])

    count
  end

  defp force_generation(lineage, generation) do
    {:ok, _result} =
      Repo.query("UPDATE session_authorities SET generation = $2 WHERE lineage = $1", [
        Ecto.UUID.dump!(lineage),
        generation
      ])
  end

  defp insert_authority(lineage, human_account_id, generation, revoked_at) do
    Repo.query(
      """
      INSERT INTO session_authorities
        (lineage, human_account_id, generation, revoked_at, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, now(), now())
      """,
      [Ecto.UUID.dump!(lineage), human_account_id, generation, revoked_at]
    )
  end
end
