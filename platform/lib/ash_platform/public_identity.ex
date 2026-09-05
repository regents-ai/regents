defmodule AshPlatform.PublicIdentity do
  @moduledoc """
  Resolves the public name and picture for a signed human without exposing its
  private identity.

  A wallet that publishes an ENS name is called by it and drawn with the picture
  that name carries; a wallet that publishes neither is called by its shortened
  address and drawn with a picture generated from that address.
  """

  @wallet ~r/\A0x[0-9a-fA-F]{40}\z/

  def label(identity) when is_map(identity) do
    identity
    |> preferred_labels()
    |> Enum.find_value(&present/1)
    |> case do
      nil -> short_wallet(Map.get(identity, :wallet_address))
      label -> label
    end
  end

  def label(_identity), do: "Account"

  def avatar_src(identity) when is_map(identity) do
    case present(Map.get(identity, :ens_avatar_url)) do
      nil -> generated_avatar(Map.get(identity, :wallet_address))
      avatar -> avatar
    end
  end

  def avatar_src(_identity), do: nil

  defp generated_avatar(wallet) do
    case normalize_wallet(wallet) do
      nil -> nil
      wallet -> wallet_avatar(wallet)
    end
  end

  defp preferred_labels(identity) do
    [
      Map.get(identity, :display_name),
      Map.get(identity, :regent_nameclaim),
      Map.get(identity, :ens_name)
    ]
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(_value), do: nil

  defp short_wallet(<<"0x", hex::binary-size(40)>> = wallet) do
    if String.match?(hex, ~r/\A[0-9a-fA-F]{40}\z/),
      do: "#{String.slice(wallet, 0, 6)}…#{String.slice(wallet, -4, 4)}",
      else: "Account"
  end

  defp short_wallet(_wallet), do: "Account"

  defp normalize_wallet(wallet) when is_binary(wallet) do
    wallet = String.trim(wallet)
    if Regex.match?(@wallet, wallet), do: String.downcase(wallet)
  end

  defp normalize_wallet(_wallet), do: nil

  defp wallet_avatar(wallet) do
    digest = :crypto.hash(:sha256, wallet)
    bytes = :binary.bin_to_list(digest)
    [red, green, blue, red2, green2, blue2 | cells] = bytes

    primary = color(red, green, blue)
    secondary = color(red2, green2, blue2)

    marks =
      for row <- 0..4,
          column <- 0..2,
          value = Enum.at(cells, row * 3 + column),
          rem(value, 3) != 0,
          mirrored_column <- mirrored_columns(column) do
        fill = if rem(value, 3) == 1, do: primary, else: secondary
        ~s(<rect x="#{mirrored_column}" y="#{row}" width="1" height="1" fill="#{fill}"/>)
      end
      |> Enum.join()

    svg =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 5 5" shape-rendering="crispEdges"><rect width="5" height="5" fill="#121212"/>#{marks}</svg>)

    "data:image/svg+xml;base64," <> Base.encode64(svg)
  end

  defp mirrored_columns(0), do: [0, 4]
  defp mirrored_columns(1), do: [1, 3]
  defp mirrored_columns(2), do: [2]

  defp color(red, green, blue) do
    "rgb(#{bright(red)},#{bright(green)},#{bright(blue)})"
  end

  defp bright(component), do: 72 + rem(component, 168)
end
