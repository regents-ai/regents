defmodule RegentsWeb.RedeemGalleryLiveTest do
  use RegentsWeb.ConnCase, async: false

  alias Regents.Accounts
  alias Regents.Accounts.SessionAuthority
  alias Regents.Actors.System
  alias RegentsWeb.SessionAuthorityHelpers

  # Every OpenSea request waits for the test to let it answer, with one Regents
  # Club pass in each wallet.
  setup do
    test = self()

    Application.put_env(:regents, :test_open_sea_handler, fn url ->
      send(test, {:held, self()})

      receive do
        :release -> :ok
      end

      nfts = if String.contains?(url, "regents-club"), do: [%{"identifier" => "1123"}], else: []
      {:ok, %{status: 200, body: %{"nfts" => nfts}}}
    end)

    on_exit(fn -> Application.delete_env(:regents, :test_open_sea_handler) end)
  end

  test "MY_PASSES: the account's own passes are found and shown", %{conn: conn} do
    {view, _session} = open_gallery(conn, "gallery-mine")

    view |> element("#gallery-mine") |> render_click()
    assert render(view) =~ "Finding your passes…"

    release_lookups()
    render_async(view)

    assert has_element?(view, "#my-pass-1123")
    assert render(view) =~ "You hold 1 pass."
  end

  test "LATE_GALLERY_RESULT: passes found for a session that has since ended are never shown",
       %{conn: conn} do
    {view, session} = open_gallery(conn, "gallery-late")

    view |> element("#gallery-mine") |> render_click()
    assert_receive {:held, held}

    # The session ends without the page being told: its next event finds no
    # account behind it.
    SessionAuthority.revoke(SessionAuthority.claim(session))
    view |> element("#gallery-mine") |> render_click()

    release_lookups([held])
    render_async(view)

    refute has_element?(view, "#my-pass-1123")
    refute render(view) =~ "You hold"
  end

  test "LEAVING_THE_GALLERY: passes found after leaving belong to the same account", %{
    conn: conn
  } do
    {view, _session} = open_gallery(conn, "gallery-leave")

    view |> element("#gallery-mine") |> render_click()
    assert_receive {:held, held}
    render_patch(view, "/stake")

    release_lookups([held])
    render_async(view)
    refute has_element?(view, "#my-pass-1123")

    render_patch(view, "/redeem/gallery")
    assert has_element?(view, "#my-pass-1123")
  end

  defp open_gallery(conn, suffix) do
    unique = Elixir.System.unique_integer([:positive])
    wallet = "0x" <> String.pad_leading(Integer.to_string(unique, 16), 40, "0")

    {:ok, account} =
      Accounts.register_verified("did:privy:#{suffix}:#{unique}", wallet, [wallet],
        actor: %System{}
      )

    session = SessionAuthorityHelpers.signed_in_session(account.id)
    {:ok, view, _html} = conn |> init_test_session(session) |> live("/redeem/gallery")
    {view, session}
  end

  # Lets every held request answer, including ones that start while others end.
  defp release_lookups(held \\ []) do
    Enum.each(held, &send(&1, :release))

    receive do
      {:held, pid} -> release_lookups([pid])
    after
      200 -> :ok
    end
  end
end
