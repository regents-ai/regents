defmodule AshPlatform.Names.ClaimFreeTest do
  @moduledoc """
  A free claim writes two protected tables. Invariants: a name is recorded only
  together with one free claim spent on the claimer's own wallet, and a refused
  claim changes neither table.
  """
  use AshPlatformWeb.ConnCase, async: false

  import AshPlatform.NamesFixtures

  alias AshPlatform.Actors.Human
  alias AshPlatform.Names
  alias AshPlatform.Repo

  @main "0x7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a"
  @linked "0x7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b"
  @stranger "0x7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c"

  setup_all do
    ensure_claims_table!()
  end

  defp actor(wallets), do: %Human{human_account_id: 1, wallet_addresses: wallets}

  defp used(address) do
    %{rows: [[used]]} =
      Repo.query!(
        "SELECT free_mints_used FROM regent_names.basenames_mint_allowances WHERE address = $1",
        [address]
      )

    used
  end

  defp claim_count do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM regent_names.basenames_mints")
    count
  end

  test "a claim records the name for the claimer's wallet and spends one free claim" do
    insert_allowance(String.upcase(@main), 2, 0)

    assert {:ok, claim} = Names.claim_free_name("fresh-name", actor: actor([@main]))

    assert claim.ens_fqdn == "fresh-name.regent.eth"
    assert claim.fqdn == "fresh-name.agent.base.eth"
    assert String.downcase(claim.owner_address) == @main
    assert claim.claim_status == "reserved"
    assert claim.is_free
    assert is_nil(claim.tx_hash)
    assert claim.node =~ ~r/^0x[0-9a-f]{64}$/
    assert used(claim.owner_address) == 1

    assert {:ok, %{results: [mine]}} = Names.list_my_claims(actor: actor([@main]))
    assert mine.id == claim.id
  end

  test "the main wallet's free claim is spent before a linked wallet's" do
    insert_allowance(@linked, 1, 0)
    insert_allowance(@main, 1, 0)

    assert {:ok, first} = Names.claim_free_name("first-name", actor: actor([@main, @linked]))
    assert {:ok, second} = Names.claim_free_name("second-name", actor: actor([@main, @linked]))

    assert {first.owner_address, second.owner_address} == {@main, @linked}
    assert {used(@main), used(@linked)} == {1, 1}
  end

  test "a refused claim records nothing and spends nothing" do
    insert_allowance(@main, 1, 0)
    insert_allowance(@stranger, 5, 0)
    insert_claim(7_000_001, @stranger, %{label: "taken", fqdn: "taken.agent.base.eth"})

    # The name is held, the name breaks the rules, the claimer has no free claim
    # (a stranger's is never spent), and nobody is signed in.
    assert {:error, %Ash.Error.Invalid{}} = Names.claim_free_name("taken", actor: actor([@main]))
    assert {:error, %Ash.Error.Invalid{}} = Names.claim_free_name("-Bad", actor: actor([@main]))

    assert {:error, %Ash.Error.Invalid{}} =
             Names.claim_free_name("no-allowance", actor: actor([@linked]))

    assert {:error, %Ash.Error.Forbidden{}} = Names.claim_free_name("anonymous", actor: nil)

    assert claim_count() == 1
    assert {used(@main), used(@stranger)} == {0, 0}
  end

  test "a wallet's last free claim cannot be spent twice" do
    insert_allowance(@main, 1, 0)

    assert {:ok, _claim} = Names.claim_free_name("only-name", actor: actor([@main]))

    assert {:error, %Ash.Error.Invalid{}} =
             Names.claim_free_name("one-more", actor: actor([@main]))

    assert claim_count() == 1
    assert used(@main) == 1
  end
end
