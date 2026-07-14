defmodule AshPlatform.Autolaunch.AuctionTokenTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch

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

    assert Enum.map(recent_records, & &1.id) |> MapSet.new() ==
             MapSet.new([recent.id, featured.id])

    assert {:ok, [featured_record]} = Autolaunch.list_featured_auctions()
    assert featured_record.id == featured.id
    assert {:ok, public} = Autolaunch.get_public_auction(recent.id)
    assert public.title == "Recent auction"
  end

  test "top and recently graduated tokens require explicit public facts" do
    auction = auction!()
    graduated_at = DateTime.utc_now()

    ranked =
      Autolaunch.import_token!(
        auction.id,
        "Regent One",
        "RONE",
        "A graduated token.",
        graduated_at,
        1,
        actor: %System{}
      )

    unranked =
      Autolaunch.import_token!(
        auction.id,
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

  test "imports reject missing and lookalike system actors" do
    for actor <- [nil, %{role: :system}, %{role: :human, human_account_id: 1}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.import_auction("Nope", nil, false, :created, nil, actor: actor)
    end
  end

  defp auction! do
    Autolaunch.import_auction!("Token auction", nil, false, :graduated, DateTime.utc_now(),
      actor: %System{}
    )
  end
end
