defmodule AshPlatform.Autolaunch.AuctionTokenTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch
  alias AshPlatform.Autolaunch.Auction

  test "public auction reads separate recent and explicitly featured records" do
    recent =
      Autolaunch.import_auction!(
        "Recent auction",
        "A newly created launch.",
        false,
        :created,
        nil,
        actor: %System{}
      )

    featured =
      Autolaunch.import_auction!(
        "Featured auction",
        "An editorially featured launch.",
        true,
        :active,
        DateTime.utc_now(),
        actor: %System{}
      )

    assert {:ok, recent_records} = Autolaunch.list_recent_auctions()

    recent_ids = MapSet.new(Enum.map(recent_records, & &1.id))
    assert MapSet.subset?(MapSet.new([recent.id, featured.id]), recent_ids)

    assert {:ok, [featured_record]} = Autolaunch.list_featured_auctions()
    assert featured_record.id == featured.id
    assert {:ok, public} = Autolaunch.get_public_auction(recent.id)
    assert public.title == "Recent auction"
  end

  test "top and recently graduated tokens require explicit public facts" do
    ranked_auction = auction!()
    unranked_auction = auction!()
    graduated_at = DateTime.utc_now()

    ranked =
      Autolaunch.import_token!(
        ranked_auction.id,
        "Regent One",
        "RONE",
        "A graduated token.",
        graduated_at,
        1,
        actor: %System{}
      )

    unranked =
      Autolaunch.import_token!(
        unranked_auction.id,
        "Regent Two",
        "RTWO",
        nil,
        graduated_at,
        nil,
        actor: %System{}
      )

    assert {:ok, [top]} = Autolaunch.list_top_tokens()
    assert top.id == ranked.id

    assert {:ok, graduated} = Autolaunch.list_recently_graduated_tokens()
    assert MapSet.new(Enum.map(graduated, & &1.id)) == MapSet.new([ranked.id, unranked.id])
    assert {:ok, nil} = Autolaunch.get_public_token(Ash.UUID.generate())
  end

  test "one auction cannot import more than one token" do
    auction = auction!()

    first =
      Autolaunch.import_token!(
        auction.id,
        "Canonical Auction Token",
        "CAN",
        nil,
        DateTime.utc_now(),
        nil,
        actor: %System{}
      )

    assert {:error, %Ash.Error.Invalid{} = error} =
             Autolaunch.import_token(
               auction.id,
               "Duplicate Auction Token",
               "DUP",
               nil,
               DateTime.utc_now(),
               nil,
               actor: %System{}
             )

    assert Exception.message(error) =~ "auction_id"
    assert Exception.message(error) =~ "has already been taken"

    assert {:ok, tokens} = Autolaunch.list_tokens()
    assert Enum.map(tokens, & &1.id) == [first.id]
  end

  test "imports reject missing and lookalike system actors" do
    for actor <- [nil, %{role: :system}, %{role: :human, human_account_id: 1}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.import_auction("Nope", nil, false, :created, nil, actor: actor)
    end
  end

  test "launchpad search treats adapter wildcards and Unicode as literal text" do
    nonce = Integer.to_string(Elixir.System.unique_integer([:positive]))

    percent = projected_auction!("Percent %#{nonce}", "PL#{nonce}")
    underscore = projected_auction!("Underscore _#{nonce}", "UL#{nonce}")
    slash = projected_auction!("Slash \\#{nonce}", "SL#{nonce}")
    unicode = projected_auction!("猫の市場 #{nonce}", "CAT#{nonce}")

    for {query, expected} <- [
          {"%#{nonce}", percent},
          {"_#{nonce}", underscore},
          {"\\#{nonce}", slash},
          {"猫の市場 #{nonce}", unicode}
        ] do
      assert {:ok, records} = Autolaunch.list_active_launchpad_auctions(query, [])
      assert Enum.map(records, & &1.id) == [expected.id]
    end
  end

  test "launchpad search covers presentation, mixed-case addresses, creator batches and bounds" do
    nonce = Elixir.System.unique_integer([:positive])
    creator = account!(nonce)
    address = "0xAbCdEf0000000000000000000000000000000001"

    auction =
      projected_auction!("Searchable Launch #{nonce}", "FIND#{nonce}",
        summary: "One exact description #{nonce}",
        address: address,
        creator_human_account_id: creator.id
      )

    token =
      Autolaunch.import_token!(
        auction.id,
        "Graduated Search #{nonce}",
        "GRAD#{nonce}",
        "Token description #{nonce}",
        DateTime.utc_now(),
        nil,
        actor: %System{}
      )

    for query <- [
          "SEARCHABLE LAUNCH #{nonce}",
          "find#{nonce}",
          "description #{nonce}",
          String.upcase(address)
        ] do
      assert {:ok, records} = Autolaunch.list_active_launchpad_auctions(query, [])
      assert Enum.any?(records, &(&1.id == auction.id))
    end

    assert {:ok, by_creator} =
             Autolaunch.list_active_launchpad_auctions("no-text-match", [creator.id])

    assert Enum.any?(by_creator, &(&1.id == auction.id))

    for query <- ["GRAD#{nonce}", "token description #{nonce}", String.upcase(address)] do
      assert {:ok, records} = Autolaunch.list_graduated_launchpad_tokens(query, [])
      assert Enum.any?(records, &(&1.id == token.id))
    end

    assert {:ok, active} = Autolaunch.list_active_launchpad_auctions("", [])
    assert length(active) <= 8

    assert {:ok, explored} = Autolaunch.list_explore_launchpad_auctions("", [])
    assert length(explored) <= 24

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.list_active_launchpad_auctions(String.duplicate("x", 81), [])
  end

  defp auction! do
    Autolaunch.import_auction!("Token auction", nil, false, :graduated, DateTime.utc_now(),
      actor: %System{}
    )
  end

  defp projected_auction!(title, symbol, options \\ []) do
    address = Keyword.get(options, :address)

    Auction
    |> Ash.Changeset.for_create(
      :project_lab,
      %{
        projection_id: Ash.UUID.generate(),
        title: title,
        summary: Keyword.get(options, :summary),
        token_symbol: symbol,
        creator_human_account_id: Keyword.get(options, :creator_human_account_id),
        featured: false,
        state: :active,
        auction_address: address,
        current_clearing_price: "1"
      },
      domain: Autolaunch,
      actor: %System{}
    )
    |> Ash.create!(domain: Autolaunch, actor: %System{})
  end

  defp account!(nonce) do
    wallet = "0x" <> String.pad_leading(Integer.to_string(nonce, 16), 40, "0")

    AshPlatform.Accounts.register_verified!(
      "did:privy:auction-search:#{nonce}",
      wallet,
      [wallet],
      actor: %System{}
    )
  end
end
