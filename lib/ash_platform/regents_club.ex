defmodule AshPlatform.RegentsClub do
  @moduledoc false

  alias AshPlatform.WalletActions.{Abi, Address}

  @manifest_path Path.expand("../../contracts/base-mainnet.json", __DIR__)
  @abi_path Path.expand("../../contracts/abi/regents-club.json", __DIR__)
  @external_resource @manifest_path
  @external_resource @abi_path

  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @contract get_in(@manifest, ["contracts", "regents_club"])
  @abi_contents File.read!(@abi_path)
  @abi Jason.decode!(@abi_contents)
  @abi_sha256 :crypto.hash(:sha256, @abi_contents) |> Base.encode16(case: :lower)

  @chain_id 8453
  @contract_address "0x2208aaDBdEcd47D3B4430b5b75a175f6d885D487"
  @owner "0x45c9a201e2937608905fef17de9a67f25f9f98e0"
  @new_base_uri "https://media.regents.sh/metadata/"
  @old_base_uri "https://regents.sh/metadata/"
  @first_token_id 1
  @last_token_id 1998
  @action "set_base_uri"
  @selector "0x55f804b3"
  @owner_selector "0x8da5cb5b"
  @base_uri_selector "0x6c0360eb"
  @token_uri_selector "0xc87b56dd"
  @total_supply_selector "0x18160ddd"
  @supports_interface_selector "0x01ffc9a7"
  @erc4906_interface_id "0x49064906"
  @batch_topic "0x6bd5c950a8d8df17f772f5af37cb3655737899cbf903264b9795592da439661c"

  @calldata "0x55f804b30000000000000000000000000000000000000000000000000000000000000020" <>
              "0000000000000000000000000000000000000000000000000000000000000022" <>
              "68747470733a2f2f6d656469612e726567656e74732e73682f6d657461646174612f" <>
              "000000000000000000000000000000000000000000000000000000000000"

  @after_compile __MODULE__

  def __after_compile__(_env, _bytecode) do
    expected = [
      {"function", "owner()"},
      {"function", "baseURI()"},
      {"function", "tokenURI(uint256)"},
      {"function", "totalSupply()"},
      {"function", "supportsInterface(bytes4)"},
      {"function", "setBaseURI(string)"},
      {"event", "BatchMetadataUpdate(uint256,uint256)"}
    ]

    Enum.each(expected, fn {kind, signature} -> Abi.declared!(@abi, kind, signature) end)

    action = @contract["prepared_actions"] |> List.first()
    constants = @contract["onchain_constants"]
    media = @contract["media_release_attestation"]
    {:ok, calldata_keccak256} = runtime_hash(@calldata)

    checks = [
      get_in(@manifest, ["chain", "id"]) == @chain_id,
      Address.equal?(@contract["address"], @contract_address),
      Address.equal?(constants["owner"], @owner),
      constants["current_base_uri"] == @old_base_uri,
      constants["cutover_base_uri"] == @new_base_uri,
      constants["first_token_id"] == @first_token_id,
      constants["last_token_id"] == @last_token_id,
      constants["total_supply"] == 1998,
      constants["erc4906_interface_id"] == @erc4906_interface_id,
      constants["calldata_keccak256"] == calldata_keccak256,
      @contract["abi"]["canonical_sha256"] == @abi_sha256,
      @contract["abi"]["function_count"] == 6,
      Enum.count(@abi, &(&1["type"] == "function")) == 6,
      Enum.count(@abi, &(&1["type"] == "event")) == 1,
      match?([_, _, _, _, _, _, _], @abi),
      match?([_], @contract["prepared_actions"]),
      action["id"] == @action,
      action["signature"] == "setBaseURI(string)",
      action["selector"] == @selector,
      action["value"] == "0",
      action["argument_bindings"]["new_base_uri"] == @new_base_uri,
      Address.equal?(action["argument_bindings"]["expected_signer"], @owner),
      @contract["confirmation_event"]["topic0"] == @batch_topic,
      Abi.topic0("BatchMetadataUpdate(uint256,uint256)") == @batch_topic,
      media["full_corpus_route_count"] == @last_token_id - @first_token_id + 1,
      media["live_probe_token_ids"] == [1, 1000, 1998],
      media["operator_attestation_required"] == true,
      valid_sha256?(media["artifact_manifest_sha256"]),
      valid_sha256?(media["release_manifest_sha256"]),
      valid_sha256?(media["production_deployment_verification_sha256"]),
      valid_sha256?(media["isolated_verification_sha256"]),
      valid_image_digest?(media["active_image_digest"])
    ]

    unless Enum.all?(checks), do: raise("Regents Club authority manifest is inconsistent")
  end

  def enabled?,
    do: Application.get_env(:ash_platform, :regents_club_metadata_cutover, false) == true

  def disable! do
    Application.put_env(:ash_platform, :regents_club_metadata_cutover, false)
    :ok
  end

  def authorized_account?(%{wallet_addresses: wallets}) when is_list(wallets) do
    Enum.any?(wallets, &Address.equal?(&1, @owner))
  end

  def authorized_account?(_account), do: false

  def chain_id, do: @chain_id
  def action, do: @action
  def owner, do: @owner
  def contract_address, do: normalize!(@contract_address)
  def runtime_keccak256, do: get_in(@contract, ["runtime_code", "keccak256"])
  def runtime_bytes, do: get_in(@contract, ["runtime_code", "bytes"])
  def new_base_uri, do: @new_base_uri
  def old_base_uri, do: @old_base_uri
  def first_token_id, do: @first_token_id
  def last_token_id, do: @last_token_id
  def calldata, do: @calldata
  def selector, do: @selector
  def owner_calldata, do: @owner_selector
  def base_uri_calldata, do: @base_uri_selector
  def total_supply_calldata, do: @total_supply_selector

  def supports_erc4906_calldata,
    do:
      @supports_interface_selector <>
        String.trim_leading(@erc4906_interface_id, "0x") <> String.duplicate("0", 56)

  def erc4906_interface_id, do: @erc4906_interface_id
  def calldata_keccak256, do: get_in(@contract, ["onchain_constants", "calldata_keccak256"])
  def media_release_attestation, do: @contract["media_release_attestation"]
  def batch_metadata_topic, do: @batch_topic

  def token_uri_calldata(token_id) when token_id in [@first_token_id, @last_token_id] do
    @token_uri_selector <> (token_id |> Integer.to_string(16) |> String.pad_leading(64, "0"))
  end

  def valid_attempt_id?(attempt_id) when is_binary(attempt_id),
    do:
      String.match?(
        attempt_id,
        ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
      )

  def valid_attempt_id?(_attempt_id), do: false

  def runtime_hash("0x" <> hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} ->
        {:ok,
         "0x" <>
           Base.encode16(:jose_jwa_sha3.keccak(1088, 512, bytes, 1, 32), case: :lower)}

      :error ->
        :error
    end
  end

  def runtime_hash(_code), do: :error

  def decode_address("0x" <> hex) when byte_size(hex) == 64 do
    with true <- String.match?(String.slice(hex, 0, 24), ~r/\A0+\z/),
         {:ok, address} <- Address.normalize("0x" <> String.slice(hex, 24, 40)) do
      {:ok, address}
    else
      _ -> :error
    end
  end

  def decode_address(_value), do: :error

  def decode_uint("0x" <> hex) when byte_size(hex) == 64 do
    case Integer.parse(hex, 16) do
      {value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  def decode_uint(_value), do: :error

  def decode_bool(value) do
    case decode_uint(value) do
      {:ok, 0} -> {:ok, false}
      {:ok, 1} -> {:ok, true}
      _ -> :error
    end
  end

  def decode_string("0x" <> hex) do
    with {:ok, bytes} <- Base.decode16(hex, case: :mixed),
         <<offset::unsigned-big-integer-size(256), rest::binary>> <- bytes,
         true <- offset == 32,
         <<length::unsigned-big-integer-size(256), encoded::binary>> <- rest,
         true <- length <= byte_size(encoded),
         <<value::binary-size(length), padding::binary>> <- encoded,
         true <- rem(byte_size(encoded), 32) == 0,
         true <- byte_size(padding) < 32,
         true <- padding == :binary.copy(<<0>>, byte_size(padding)),
         true <- String.valid?(value) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  def decode_string(_value), do: :error

  def batch_metadata_event?(logs) when is_list(logs) do
    matching =
      Enum.filter(logs, fn
        %{"address" => address, "topics" => [topic], "data" => data} ->
          Address.equal?(address, contract_address()) and String.downcase(topic) == @batch_topic and
            batch_range?(data)

        _ ->
          false
      end)

    match?([_], matching)
  end

  def batch_metadata_event?(_logs), do: false

  defp batch_range?("0x" <> data) when byte_size(data) == 128 do
    with {from, ""} <- Integer.parse(String.slice(data, 0, 64), 16),
         {to, ""} <- Integer.parse(String.slice(data, 64, 64), 16) do
      from == @first_token_id and to == @last_token_id
    else
      _ -> false
    end
  end

  defp batch_range?(_data), do: false

  defp normalize!(address) do
    case Address.normalize(address) do
      {:ok, normalized} -> normalized
      :error -> raise "invalid Regents Club manifest address"
    end
  end

  defp valid_sha256?(value),
    do: is_binary(value) and String.match?(value, ~r/\A[0-9a-f]{64}\z/)

  defp valid_image_digest?("sha256:" <> digest), do: valid_sha256?(digest)
  defp valid_image_digest?(_value), do: false
end
