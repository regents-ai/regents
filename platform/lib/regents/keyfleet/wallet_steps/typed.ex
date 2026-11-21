defmodule Regents.Keyfleet.WalletSteps.Typed do
  @moduledoc """
  What a person typed into a wallet form, read strictly. Each reader answers
  `{:ok, value}` or `{:error, problem}`; the page puts the problem in words.
  Anything the call can carry is carried, and the contract decides the rest.
  """

  alias RegentChain.Address
  alias Regents.Keyfleet.Fleets.Fleet

  @largest_uint256 Integer.pow(2, 256) - 1

  @doc "The largest number a `uint256` holds."
  def largest_uint256, do: @largest_uint256

  @doc """
  Key numbers separated by commas or spaces, like `3, 7, 12`, in order and
  each once, as the contracts take a batch of keys. Nothing typed is
  `:no_keys`.
  """
  def keys(text) do
    case String.split(text, ~r/[\s,]+/, trim: true) do
      [] ->
        {:error, :no_keys}

      entries ->
        if Enum.all?(entries, &Regex.match?(~r/\A\d+\z/, &1)),
          do:
            entries |> Enum.map(&String.to_integer/1) |> Enum.sort() |> Enum.uniq() |> in_range(),
          else: {:error, :keys_unreadable}
    end
  end

  @doc "The one key a proposal is made with."
  def key(text) do
    entry = String.trim(text)

    cond do
      entry == "" ->
        {:error, :no_key}

      Regex.match?(~r/\A\d+\z/, entry) ->
        with {:ok, [key]} <- in_range([String.to_integer(entry)]), do: {:ok, key}

      true ->
        {:error, :key_unreadable}
    end
  end

  @doc "The key a proposal acts on, read as `key/1` reads the key it is made with."
  def target(text) do
    case key(text) do
      {:ok, target} -> {:ok, target}
      {:error, :no_key} -> {:error, :no_target}
      {:error, :key_unreadable} -> {:error, :target_unreadable}
      {:error, problem} -> {:error, problem}
    end
  end

  @doc "How many days a shard lasts: a whole number from 1 to 365."
  def days(text) do
    entry = String.trim(text)

    with true <- Regex.match?(~r/\A\d{1,3}\z/, entry),
         days when days in 1..365 <- String.to_integer(entry) do
      {:ok, days}
    else
      _other -> {:error, :days_unreadable}
    end
  end

  # Key 0 and numbers past the fleet's last token id name no Key.
  defp in_range(keys) do
    if Enum.all?(keys, &Fleet.key_number?/1), do: {:ok, keys}, else: {:error, :key_too_large}
  end

  @doc """
  An address, in lowercase. One written in mixed case has to pass its
  checksum; the zero address is never one.
  """
  def address(text, problem) do
    case Address.normalize(String.trim(text)) do
      {:ok, address} -> {:ok, address}
      :error -> {:error, problem}
    end
  end

  @doc """
  An amount in whole tokens, exactly, in the token's smallest units. Commas
  may only group thousands, and a point marks decimals. Zeros at the end of
  the decimals change nothing; more decimal places than the token has can't
  be paid, so they aren't rounded.
  """
  def amount(text, decimals, largest) do
    entry = String.trim(text)

    if Regex.match?(~r/\A\d{1,3}(?:,\d{3})+(?:\.\d+)?\z/, entry) or
         Regex.match?(~r/\A\d+(?:\.\d+)?\z/, entry) do
      {whole, written} =
        case entry |> String.replace(",", "") |> String.split(".") do
          [whole] -> {whole, ""}
          [whole, written] -> {whole, written}
        end

      units(whole, String.trim_trailing(written, "0"), decimals, largest)
    else
      {:error, if(String.contains?(entry, ","), do: :amount_commas, else: :amount_unreadable)}
    end
  end

  defp units(_whole, fraction, decimals, _largest) when byte_size(fraction) > decimals,
    do: {:error, {:too_many_decimals, decimals}}

  defp units(whole, fraction, decimals, largest) do
    units = String.to_integer(whole <> String.pad_trailing(fraction, decimals, "0"))
    if units > largest, do: {:error, :amount_too_large}, else: {:ok, units}
  end

  @doc """
  A daily split rate written as a percent, like `0.5`, in basis points:
  from 0.1% to 2%, to two decimal places.
  """
  def rate(text) do
    with {:ok, hundredths} <- amount(text, 2, @largest_uint256),
         true <- hundredths in 10..200 do
      {:ok, hundredths}
    else
      _other -> {:error, :rate_unreadable}
    end
  end

  @doc """
  A share of a treasury balance written as a percent, like `2.5`, in parts
  per million: from 0.0001% to 99%, to four decimal places.
  """
  def share(text) do
    with {:ok, ppm} <- amount(text, 4, @largest_uint256),
         true <- ppm in 1..990_000 do
      {:ok, ppm}
    else
      _other -> {:error, :share_unreadable}
    end
  end

  @doc """
  Whether a Key's edits are restricted: `"true"` or `"false"`, nothing else.
  """
  def restricted("true"), do: {:ok, true}
  def restricted("false"), do: {:ok, false}
  def restricted(_text), do: {:error, :restricted_unreadable}

  @doc """
  Text up to `bytes` long, trimmed; nothing typed is `{:missing, name}` and
  more is `{:too_long, name, bytes}`.
  """
  def text(text, name, bytes) do
    entry = String.trim(text)

    cond do
      entry == "" -> {:error, {:missing, name}}
      byte_size(entry) > bytes -> {:error, {:too_long, name, bytes}}
      true -> {:ok, entry}
    end
  end
end
