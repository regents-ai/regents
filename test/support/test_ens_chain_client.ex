defmodule AshPlatform.TestEnsChainClient do
  @moduledoc """
  A stubbed Ethereum mainnet for ENS reads.

  Every answer is chosen by the record being asked for, so no test reaches a real
  endpoint and cases stay independent of one another. `wallets/0` names the
  wallets this chain knows and what each of them publishes.
  """

  @behaviour AgentEns.Internal.RPC

  alias AgentEns.Internal.ABI
  alias AgentEns.Verify

  @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
  @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
  @registry_owner "0x1111111111111111111111111111111111111111"
  @no_address "0x0000000000000000000000000000000000000000"
  @extended_resolver_interface "9061b923"

  @wallets %{
    named_with_avatar: %{
      wallet: "0xaaaa000000000000000000000000000000000001",
      name: "atlas.eth",
      avatar: "https://avatars.regents.test/atlas.png",
      owner: :itself
    },
    named_without_avatar: %{
      wallet: "0xaaaa000000000000000000000000000000000002",
      name: "plain.eth",
      avatar: "",
      owner: :itself
    },
    named_with_unsupported_avatar: %{
      wallet: "0xaaaa000000000000000000000000000000000003",
      name: "ipfs-avatar.eth",
      avatar: "ipfs://bafyfakeavatarcid",
      owner: :itself
    },
    unnamed: %{
      wallet: "0xaaaa000000000000000000000000000000000004",
      name: "",
      avatar: "",
      owner: :itself
    },
    # Publishes a reverse record for a name whose own address record points
    # somewhere else, which is the case a forward check exists to reject.
    impostor: %{
      wallet: "0xaaaa000000000000000000000000000000000005",
      name: "someone-else.eth",
      avatar: "https://avatars.regents.test/someone-else.png",
      owner: "0xbbbb000000000000000000000000000000000009"
    },
    unreachable: %{
      wallet: "0xaaaa000000000000000000000000000000000006",
      name: "",
      avatar: "",
      owner: :itself
    },
    slow: %{
      wallet: "0xaaaa000000000000000000000000000000000007",
      name: "",
      avatar: "",
      owner: :itself
    }
  }

  @doc "The wallets this stubbed chain knows, by the story each one tells."
  def wallets, do: @wallets

  @doc "The wallet address for one of `wallets/0`."
  def wallet(story), do: @wallets |> Map.fetch!(story) |> Map.fetch!(:wallet)

  @doc "What one of `wallets/0` publishes on this chain."
  def published(story), do: Map.fetch!(@wallets, story)

  @impl true
  def eth_call(_rpc_url, to, data), do: answer(String.downcase(to), selector(data), data)

  defp answer(@ens_registry, selector, data) do
    cond do
      selector == ABI.selector("recordExists(bytes32)") -> {:ok, bool_word(true)}
      selector == ABI.selector("owner(bytes32)") -> {:ok, address_word(@registry_owner)}
      selector == ABI.selector("ttl(bytes32)") -> {:ok, uint_word(0)}
      selector == ABI.selector("resolver(bytes32)") -> resolver_of(namehash_of(data))
    end
  end

  defp answer(@resolver, selector, data) do
    cond do
      selector == ABI.selector("supportsInterface(bytes4)") -> {:ok, supports(data)}
      selector == ABI.selector("name(bytes32)") -> {:ok, string_word(reverse_record(data))}
      selector == ABI.selector("addr(bytes32)") -> {:ok, address_word(address_record(data))}
      selector == ABI.selector("text(bytes32,string)") -> {:ok, string_word(avatar_record(data))}
    end
  end

  # The two wallets whose chain never answers usefully: one refuses outright, the
  # other takes longer than any lookup is allowed to wait.
  defp resolver_of(node) do
    case reversing(node) do
      {:unreachable, _published} ->
        {:error, {:rpc_call_failed, %{to: @ens_registry, reason: :nxdomain}}}

      {:slow, _published} ->
        Process.sleep(:timer.seconds(1))
        {:ok, address_word(@resolver)}

      _answering ->
        {:ok, address_word(@resolver)}
    end
  end

  # Every resolver profile but the extended one, which would send reads out to a
  # gateway this stub does not stand in for.
  defp supports(data),
    do: bool_word(not String.starts_with?(data, selector(data) <> @extended_resolver_interface))

  defp reverse_record(data) do
    case reversing(namehash_of(data)) do
      {_story, %{name: name}} -> name
      nil -> ""
    end
  end

  defp address_record(data) do
    case named(namehash_of(data)) do
      {_story, %{owner: :itself, wallet: wallet}} -> wallet
      {_story, %{owner: owner}} -> owner
      nil -> @no_address
    end
  end

  defp avatar_record(data) do
    case named(namehash_of(data)) do
      {_story, %{avatar: avatar}} -> avatar
      nil -> ""
    end
  end

  defp reversing(node), do: find(node, &reverse_name(&1.wallet))

  defp named(node), do: find(node, & &1.name)

  defp find(node, record) do
    Enum.find_value(@wallets, fn {story, published} ->
      record = record.(published)
      if record != "" and node?(record, node), do: {story, published}
    end)
  end

  defp reverse_name("0x" <> address), do: address <> ".addr.reverse"

  defp node?(name, node) do
    {:ok, expected} = Verify.namehash(name)
    Base.encode16(expected, case: :lower) == node
  end

  defp selector(data), do: String.slice(data, 0, 10)
  defp namehash_of(data), do: String.slice(data, 10, 64)

  defp uint_word(value), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")
  defp bool_word(true), do: "0x" <> String.pad_leading("1", 64, "0")
  defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

  defp address_word(address),
    do: "0x" <> String.pad_leading(String.replace_prefix(address, "0x", ""), 64, "0")

  defp string_word(value) do
    hex = Base.encode16(value, case: :lower)
    padding = rem(64 - rem(byte_size(hex), 64), 64)

    "0x" <>
      String.pad_leading("20", 64, "0") <>
      String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
      hex <> String.duplicate("0", padding)
  end
end
