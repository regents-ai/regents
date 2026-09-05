defmodule AshPlatform.TestEnsAvatarHttpClient do
  @moduledoc """
  A stubbed web for the one question asked of a name's picture: is it served?

  Every answer is chosen by the address being asked about, so no test reaches a
  real host. `addresses/0` names the addresses this web knows and what each of
  them does.
  """

  @service "https://metadata.ens.domains/mainnet/avatar/"

  @addresses %{
    "https://avatars.regents.test/atlas.png" => {:ok, 200},
    "https://avatars.regents.test/someone-else.png" => {:ok, 200},
    # A picture the name still points at, which is no longer there.
    "https://avatars.regents.test/gone.png" => {:ok, 404},
    # An `ipfs://` record and an NFT reference, both resolved by the service.
    (@service <> "ipfs-avatar.eth") => {:ok, 200},
    (@service <> "nft-avatar.eth") => {:ok, 200},
    # A record the service itself cannot resolve to a picture.
    (@service <> "unresolvable-avatar.eth") => {:ok, 404},
    # A host that will not answer at all.
    "https://avatars.regents.test/refused.png" => {:error, :nxdomain}
  }

  @doc "The addresses this stubbed web knows, by what each one does."
  def addresses, do: @addresses

  def head(url, _options) do
    case Map.fetch(@addresses, url) do
      {:ok, {:ok, status}} -> {:ok, %Req.Response{status: status}}
      {:ok, {:error, reason}} -> {:error, reason}
      :error -> raise "the stubbed web was asked about an address it does not know: #{url}"
    end
  end
end
