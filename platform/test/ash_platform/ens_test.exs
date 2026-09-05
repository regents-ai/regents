defmodule AshPlatform.EnsTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Ens, PublicIdentity, TestEnsChainClient, VerifiedPrivyIdentity}
  alias AshPlatform.Accounts.VerifiedSession
  alias AshPlatform.Actors.{Human, System}

  test "a wallet with an ENS name and picture is called and drawn by them" do
    identity = :named_with_avatar |> account() |> resolve()

    assert %{ens_name: "atlas.eth", ens_avatar_url: "https://avatars.regents.test/atlas.png"} =
             identity

    assert PublicIdentity.label(identity) == "atlas.eth"
    assert PublicIdentity.avatar_src(identity) == "https://avatars.regents.test/atlas.png"
  end

  test "a wallet with an ENS name and no picture keeps its generated one" do
    identity = :named_without_avatar |> account() |> resolve()

    assert %{ens_name: "plain.eth", ens_avatar_url: nil} = identity
    assert PublicIdentity.label(identity) == "plain.eth"
    assert "data:image/svg+xml;base64," <> _drawn = PublicIdentity.avatar_src(identity)
  end

  test "a picture published on IPFS is drawn through the ENS service" do
    identity = :named_with_ipfs_avatar |> account() |> resolve()

    assert %{
             ens_name: "ipfs-avatar.eth",
             ens_avatar_url: "https://metadata.ens.domains/mainnet/avatar/ipfs-avatar.eth"
           } = identity
  end

  test "a picture held by an NFT is drawn through the ENS service" do
    identity = :named_with_nft_avatar |> account() |> resolve()

    assert %{
             ens_name: "nft-avatar.eth",
             ens_avatar_url: "https://metadata.ens.domains/mainnet/avatar/nft-avatar.eth"
           } = identity
  end

  # A name is drawn with its own picture or with the wallet's generated one, and
  # never with a box the browser cannot fill.
  test "a record the ENS service cannot resolve keeps the generated picture" do
    identity = :named_with_unresolvable_avatar |> account() |> resolve()

    assert %{ens_name: "unresolvable-avatar.eth", ens_avatar_url: nil} = identity
    assert "data:image/svg+xml;base64," <> _drawn = PublicIdentity.avatar_src(identity)
  end

  test "a picture that is no longer there keeps the generated one" do
    identity = :named_with_missing_picture |> account() |> resolve()

    assert %{ens_name: "gone.eth", ens_avatar_url: nil} = identity
    assert "data:image/svg+xml;base64," <> _drawn = PublicIdentity.avatar_src(identity)
  end

  # The name was read before the picture was asked about, so the picture's host
  # cannot cost the name.
  test "a picture whose host will not answer keeps the name and the generated picture" do
    identity = :named_with_refused_picture |> account() |> resolve()

    assert %{ens_name: "refused.eth", ens_avatar_url: nil} = identity
    assert PublicIdentity.label(identity) == "refused.eth"
    assert "data:image/svg+xml;base64," <> _drawn = PublicIdentity.avatar_src(identity)
  end

  test "a wallet with no ENS name keeps its shortened address and generated picture" do
    identity = :unnamed |> account() |> resolve()

    assert %{ens_name: nil, ens_avatar_url: nil} = identity
    assert PublicIdentity.label(identity) == "0xaaaa…0004"

    assert PublicIdentity.avatar_src(identity) ==
             PublicIdentity.avatar_src(%{wallet_address: TestEnsChainClient.wallet(:unnamed)})
  end

  test "a name whose own record points at another wallet is not adopted" do
    identity = :impostor |> account() |> resolve()

    assert %{ens_name: nil, ens_avatar_url: nil} = identity
    assert PublicIdentity.label(identity) == "0xaaaa…0005"
  end

  test "a chain that refuses to answer keeps the last known name and picture" do
    account = account(:named_with_avatar)
    assert %{ens_name: "atlas.eth"} = resolve(account)

    assert %{ens_name: "atlas.eth", ens_avatar_url: "https://avatars.regents.test/atlas.png"} =
             account |> moved_to(:unreachable) |> resolve()
  end

  test "a chain that never answers in time keeps the last known name and picture" do
    account = account(:named_with_avatar)
    assert %{ens_name: "atlas.eth"} = resolve(account)

    assert %{ens_name: "atlas.eth"} = account |> moved_to(:slow) |> resolve()
  end

  test "no Ethereum endpoint means no lookup at all" do
    account = account(:named_with_avatar)
    endpoint = Application.get_env(:ash_platform, :ethereum_read_rpc_url)
    Application.put_env(:ash_platform, :ethereum_read_rpc_url, nil)
    on_exit(fn -> Application.put_env(:ash_platform, :ethereum_read_rpc_url, endpoint) end)

    Phoenix.PubSub.subscribe(AshPlatform.PubSub, Ens.topic(account.id))
    assert Ens.refresh(account) == :ok
    refute_receive {:ens_lookup_finished, _account_id}, 300
    assert %{ens_name: nil} = read(account)
  end

  test "signing in looks the wallet up without waiting for the chain" do
    account = account(:named_with_avatar)
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, Ens.topic(account.id))

    {elapsed_us, {:ok, signed_in, []}} =
      :timer.tc(fn -> VerifiedSession.establish(privy_identity(:named_with_avatar)) end)

    assert signed_in.id == account.id
    assert elapsed_us < 500_000

    assert_receive {:ens_lookup_finished, _account_id}, 2_000
    assert %{ens_name: "atlas.eth"} = read(account)
  end

  test "signing in from a chain that never answers is not held up by it" do
    account = account(:slow)

    {elapsed_us, {:ok, signed_in, []}} =
      :timer.tc(fn -> VerifiedSession.establish(privy_identity(:slow)) end)

    assert signed_in.id == account.id
    assert elapsed_us < 500_000
  end

  defp account(story) do
    wallet = TestEnsChainClient.wallet(story)

    {:ok, account} =
      Accounts.register_verified("did:privy:ens:#{story}", wallet, [wallet], actor: %System{})

    account
  end

  defp moved_to(account, story) do
    wallet = TestEnsChainClient.wallet(story)
    {:ok, account} = Accounts.refresh_verified(account, wallet, [wallet], actor: %System{})
    account
  end

  defp resolve(account) do
    topic = Ens.topic(account.id)
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, topic)
    assert Ens.refresh(account) == :ok
    assert_receive {:ens_lookup_finished, _account_id}, 2_000
    Phoenix.PubSub.unsubscribe(AshPlatform.PubSub, topic)
    read(account)
  end

  defp read(%{id: id}) do
    {:ok, account} = Accounts.get_human_account(id, actor: %Human{human_account_id: id})
    account
  end

  defp privy_identity(story) do
    wallet = TestEnsChainClient.wallet(story)

    %VerifiedPrivyIdentity{
      privy_user_id: "did:privy:ens:#{story}",
      session_id: "session-#{story}",
      wallet_address: wallet,
      wallet_addresses: [wallet],
      linked_socials: []
    }
  end
end
