defmodule AshPlatform.WalletActions.SubjectPaymentAbi do
  @moduledoc """
  Encodes payment-linked subject actions from the vendored revenue implementations.

  The admitted signatures, mutability, and return values come from `PaymentLinkFactory.sol`,
  `RevenueIngressAccount.sol`, and `RevenueShareSplitterV2.sol` in the archived Platform
  revenue source. The chain admission records the exact implementation line provenance.
  """

  alias AshPlatform.WalletActions.Abi

  @payment_link_abi_path Path.expand(
                           "../../../contracts/abi/payment-link-factory.json",
                           __DIR__
                         )
  @ingress_abi_path Path.expand(
                      "../../../contracts/abi/revenue-ingress-account.json",
                      __DIR__
                    )
  @splitter_abi_path Path.expand(
                       "../../../contracts/abi/revenue-share-splitter-v2.json",
                       __DIR__
                     )
  @external_resource @payment_link_abi_path
  @external_resource @ingress_abi_path
  @external_resource @splitter_abi_path

  @uint256_max Integer.pow(2, 256) - 1
  @payment_link_created_signature "PaymentLinkCreated(bytes32,address,address,string,bool)"
  @payment_link_created_topic0 "0x06c00f03aef858d7f694c6f34c8245765bedf95c92e4341eec90f78b7d24bedb"
  @entries %{
    "create_payment_link" =>
      {"createPaymentLink(bytes32,string,bytes32)", "0x96bc6c1a", @payment_link_abi_path},
    "create_canonical_payment_link" =>
      {"createCanonicalPaymentLink(bytes32,string,bytes32)", "0xb12d629e", @payment_link_abi_path},
    "set_payment_link_canonical" =>
      {"setPaymentLinkCanonical(address,bool)", "0x706a7fa6", @payment_link_abi_path},
    "set_payment_link_receiver_state" =>
      {"setPaymentLinkReceiverState(address,bool,address)", "0xc8c05f99", @payment_link_abi_path},
    "sweep_usdc" => {"sweepUSDC(bytes32)", "0xbe25fb30", @ingress_abi_path},
    "stake" => {"stake(uint256,address)", "0x7acb7757", @splitter_abi_path},
    "unstake" => {"unstake(uint256,address)", "0x8381e182", @splitter_abi_path},
    "claim_usdc" => {"claimUSDC(address)", "0x42852610", @splitter_abi_path}
  }

  for {_id, {signature, _selector, path}} <- @entries do
    abi = path |> File.read!() |> Jason.decode!()

    unless Enum.any?(abi, fn
             %{"type" => "function", "name" => name, "inputs" => inputs} ->
               "#{name}(#{Enum.map_join(inputs, ",", & &1["type"])})" == signature

             _ ->
               false
           end) do
      raise "pinned subject payment ABI is missing #{signature}"
    end
  end

  @payment_link_abi @payment_link_abi_path |> File.read!() |> Jason.decode!()

  unless Enum.any?(@payment_link_abi, fn
           %{"type" => "event", "name" => "PaymentLinkCreated", "inputs" => inputs} ->
             "PaymentLinkCreated(#{Enum.map_join(inputs, ",", & &1["type"])})" ==
               @payment_link_created_signature

           _ ->
             false
         end) do
    raise "pinned subject payment ABI is missing #{@payment_link_created_signature}"
  end

  def payment_link_created_topic0, do: @payment_link_created_topic0

  def payment_link_created_receiver(
        %{
          "address" => emitter,
          "topics" => [topic0, subject_topic, receiver_topic, creator_topic],
          "data" => data
        },
        factory,
        subject_id
      ) do
    with true <- String.downcase(topic0) == @payment_link_created_topic0,
         true <- Abi.normalize_address!(emitter) == Abi.normalize_address!(factory),
         true <- String.downcase(subject_topic) == String.downcase(subject_id),
         {:ok, receiver} <- decode_indexed_address(receiver_topic),
         {:ok, _creator} <- decode_indexed_address(creator_topic),
         {:ok, _event_data} <- decode_payment_link_created_data(data) do
      {:ok, receiver}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  def payment_link_created_receiver(_log, _factory, _subject_id), do: :error

  def encode_payment_link_create(subject_id, label, salt, canonical) when is_boolean(canonical) do
    action = if canonical, do: "create_canonical_payment_link", else: "create_payment_link"
    {_signature, selector, _path} = Map.fetch!(@entries, action)
    label_hex = Base.encode16(label, case: :lower)
    label_size = byte_size(label)

    selector <>
      encode_bytes32!(subject_id) <>
      encode_uint256!(96) <>
      encode_bytes32!(salt) <>
      encode_uint256!(label_size) <>
      pad_dynamic(label_hex, label_size)
  end

  def encode_payment_link_canonical(receiver, canonical) when is_boolean(canonical) do
    {_signature, selector, _path} = Map.fetch!(@entries, "set_payment_link_canonical")
    selector <> encode_address!(receiver) <> encode_bool(canonical)
  end

  def encode_payment_link_state(receiver, active, replacement)
      when is_boolean(active) do
    {_signature, selector, _path} = Map.fetch!(@entries, "set_payment_link_receiver_state")

    selector <>
      encode_address!(receiver) <> encode_bool(active) <> encode_address_or_zero!(replacement)
  end

  def encode_ingress_sweep(subject_id) do
    {_signature, selector, _path} = Map.fetch!(@entries, "sweep_usdc")
    selector <> encode_bytes32!(subject_id)
  end

  def encode_stake(amount, receiver), do: encode_amount_address("stake", amount, receiver)
  def encode_unstake(amount, recipient), do: encode_amount_address("unstake", amount, recipient)

  def encode_claim_usdc(recipient) do
    {_signature, selector, _path} = Map.fetch!(@entries, "claim_usdc")
    selector <> encode_address!(recipient)
  end

  def encode_approval(spender, amount), do: Abi.encode_erc20("approve", [spender, amount])

  defp encode_amount_address(action, amount, address) do
    {_signature, selector, _path} = Map.fetch!(@entries, action)
    selector <> encode_uint256!(amount) <> encode_address!(address)
  end

  defp encode_address!(address) do
    address
    |> Abi.normalize_address!()
    |> String.trim_leading("0x")
    |> String.pad_leading(64, "0")
  end

  defp encode_address_or_zero!("0x0000000000000000000000000000000000000000"),
    do: String.duplicate("0", 64)

  defp encode_address_or_zero!(address), do: encode_address!(address)

  defp decode_indexed_address("0x" <> topic) when byte_size(topic) == 64 do
    with true <- String.match?(topic, ~r/^[0-9a-fA-F]{64}$/),
         true <- String.slice(topic, 0, 24) == String.duplicate("0", 24) do
      {:ok, Abi.normalize_address!("0x" <> String.slice(topic, 24, 40))}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp decode_indexed_address(_topic), do: :error

  defp decode_payment_link_created_data("0x" <> hex) do
    with true <- byte_size(hex) >= 192,
         true <- String.match?(hex, ~r/^[0-9a-fA-F]+$/),
         {:ok, 64} <- decode_word(String.slice(hex, 0, 64)),
         {:ok, canonical_word} <- decode_word(String.slice(hex, 64, 64)),
         true <- canonical_word in [0, 1],
         {:ok, label_size} <- decode_word(String.slice(hex, 128, 64)),
         padded_label_size = div(label_size + 31, 32) * 32,
         true <- byte_size(hex) == 192 + padded_label_size * 2,
         label_hex <- String.slice(hex, 192, label_size * 2),
         padding_hex <-
           String.slice(hex, 192 + label_size * 2, (padded_label_size - label_size) * 2),
         true <- padding_hex == String.duplicate("0", byte_size(padding_hex)),
         {:ok, label} <- Base.decode16(label_hex, case: :mixed) do
      {:ok, %{label: label, canonical: canonical_word == 1}}
    else
      _ -> :error
    end
  end

  defp decode_payment_link_created_data(_data), do: :error

  defp decode_word(word) when byte_size(word) == 64 do
    case Integer.parse(word, 16) do
      {value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  defp decode_word(_word), do: :error

  defp encode_bytes32!("0x" <> value)
       when byte_size(value) == 64 do
    if String.match?(value, ~r/^[0-9a-fA-F]+$/),
      do: String.downcase(value),
      else: raise(ArgumentError, "bytes32 value is invalid")
  end

  defp encode_bytes32!(_value), do: raise(ArgumentError, "bytes32 value is invalid")

  defp encode_bool(true), do: encode_uint256!(1)
  defp encode_bool(false), do: encode_uint256!(0)

  defp encode_uint256!(value) when is_integer(value) and value in 0..@uint256_max do
    value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")
  end

  defp encode_uint256!(_value), do: raise(ArgumentError, "uint256 value is invalid")

  defp pad_dynamic(hex, byte_size) do
    padded_bytes = div(byte_size + 31, 32) * 32
    String.pad_trailing(hex, padded_bytes * 2, "0")
  end
end
