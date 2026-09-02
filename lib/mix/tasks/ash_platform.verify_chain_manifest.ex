defmodule Mix.Tasks.AshPlatform.VerifyChainManifest do
  use Mix.Task

  @shortdoc "Verifies pinned Base contracts through bounded read-only RPC calls"
  @default_rpc_url "https://base-rpc.publicnode.com"
  @default_historical_rpc_url "https://mainnet.base.org"
  @timeout_ms 12_000
  @attempts 3
  @zero_address "0x0000000000000000000000000000000000000000"
  @probe_address "0x0000000000000000000000000000000000000001"

  @impl Mix.Task
  def run(args) do
    {opts, [], []} =
      OptionParser.parse(args,
        strict: [rpc_url: :string, historical_rpc_url: :string, contract: :string]
      )

    rpc_url = opts[:rpc_url] || @default_rpc_url
    historical_rpc_url = opts[:historical_rpc_url] || @default_historical_rpc_url
    selection = opts[:contract] || "all"
    cast = find_cast!()
    root = File.cwd!()
    manifest = root |> Path.join("contracts/base-mainnet.json") |> read_json!()

    unless selection in ["all", "staking", "redemption", "regents-club"] do
      Mix.raise("--contract must be one of: all, staking, redemption, regents-club")
    end

    assert_equal!(
      cast!(cast, ["chain-id", "--rpc-url", rpc_url], "Base chain id"),
      "8453",
      "Base chain id"
    )

    assert_equal!(
      cast!(cast, ["chain-id", "--rpc-url", historical_rpc_url], "historical Base chain id"),
      "8453",
      "historical Base chain id"
    )

    if selection in ["all", "staking"] do
      verify_staking!(cast, rpc_url, historical_rpc_url, root, manifest)
      verify_multicall3!(cast, rpc_url, root)
    end

    if selection in ["all", "redemption"] do
      verify_redemption!(cast, rpc_url, historical_rpc_url, root, manifest)
    end

    if selection in ["all", "regents-club"] do
      verify_regents_club!(cast, rpc_url, root, manifest)
    end

    Mix.shell().info(
      "Verified #{selection} Base contract evidence without sending a transaction."
    )
  end

  defp verify_regents_club!(cast, rpc_url, root, manifest) do
    Mix.shell().info("Verifying Regents Club metadata cutover evidence...")
    contract = manifest["contracts"]["regents_club"]
    address = contract["address"]
    constants = contract["onchain_constants"]
    action = List.first(contract["prepared_actions"])

    assert_equal!(address, "0x2208aaDBdEcd47D3B4430b5b75a175f6d885D487", "Regents Club address")
    verify_runtime!(cast, rpc_url, "regents_club", contract)

    abi_path = Path.join([root, "contracts", contract["abi"]["path"]])
    abi_sha256 = :crypto.hash(:sha256, File.read!(abi_path)) |> Base.encode16(case: :lower)
    assert_equal!(abi_sha256, contract["abi"]["canonical_sha256"], "Regents Club ABI digest")

    assert_address!(
      call_one!(cast, rpc_url, address, "owner()(address)"),
      "0x45C9a201e2937608905fEF17De9A67f25F9f98E0",
      "Regents Club owner"
    )

    assert_equal!(
      call_one!(cast, rpc_url, address, "totalSupply()(uint256)")
      |> integer_value!("Regents Club totalSupply"),
      1998,
      "Regents Club totalSupply"
    )

    assert_equal!(
      call_one!(cast, rpc_url, address, "supportsInterface(bytes4)(bool)", ["0x49064906"]),
      true,
      "Regents Club ERC-4906 support"
    )

    old_uri = constants["current_base_uri"]
    assert_equal!(call_one!(cast, rpc_url, address, "baseURI()(string)"), old_uri, "baseURI")

    for token_id <- [1, 1998] do
      assert_equal!(
        call_one!(cast, rpc_url, address, "tokenURI(uint256)(string)", [to_string(token_id)]),
        old_uri <> to_string(token_id),
        "Regents Club tokenURI(#{token_id})"
      )
    end

    calldata =
      cast!(
        cast,
        ["calldata", "setBaseURI(string)", constants["cutover_base_uri"]],
        "Regents Club cutover calldata"
      )

    evidence =
      root
      |> Path.join("contracts/chain-contracts.yaml")
      |> YamlElixir.read_from_file!()
      |> Map.fetch!("contracts")
      |> List.first()
      |> Map.fetch!("reviewed_action_evidence")
      |> Enum.find(&(&1["contract_id"] == "regents_club"))

    assert_equal!(String.downcase(calldata), evidence["calldata"], "Regents Club calldata")
    assert_equal!(action["value"], "0", "Regents Club value")
    assert_equal!(action["selector"], "0x55f804b3", "Regents Club selector")

    assert_equal!(
      simulate_call!(
        cast,
        rpc_url,
        address,
        "setBaseURI(string)",
        [constants["cutover_base_uri"]],
        constants["owner"],
        "Regents Club owner simulation"
      ),
      "0x",
      "Regents Club owner simulation"
    )

    cast_failure!(
      cast,
      [
        "call",
        address,
        "setBaseURI(string)",
        constants["cutover_base_uri"],
        "--from",
        @probe_address,
        "--rpc-url",
        rpc_url
      ],
      "Regents Club non-owner simulation"
    )

    topic = cast!(cast, ["keccak", "BatchMetadataUpdate(uint256,uint256)"], "event topic")
    assert_equal!(String.downcase(topic), contract["confirmation_event"]["topic0"], "event topic")
  end

  # The reading aggregator is identified, never prepared against. Its identity
  # lives in chain-contracts.yaml and in module constants, because the reviewed
  # evidence manifest stays byte-for-byte frozen.
  defp verify_multicall3!(cast, rpc_url, root) do
    Mix.shell().info("Verifying the Multicall3 reading aggregator...")

    entry =
      root
      |> Path.join("contracts/chain-contracts.yaml")
      |> YamlElixir.read_from_file!()
      |> Map.fetch!("contracts")
      |> List.first()
      |> Map.fetch!("reviewed_action_evidence")
      |> Enum.find(&(&1["contract_id"] == "multicall3"))

    address = entry["address"]
    code = cast!(cast, ["code", address, "--rpc-url", rpc_url], "Multicall3 runtime")

    if code == "0x", do: Mix.raise("Multicall3 has no deployed runtime code")

    bytes = code |> String.trim_leading("0x") |> Base.decode16!(case: :mixed)
    assert_equal!(byte_size(bytes), entry["runtime_bytes"], "Multicall3 runtime byte length")

    assert_equal!(
      :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower),
      entry["runtime_sha256"],
      "Multicall3 runtime SHA-256"
    )

    assert_equal!(
      cast!(cast, ["keccak", code], "Multicall3 runtime Keccak-256") |> String.downcase(),
      entry["runtime_keccak256"],
      "Multicall3 runtime Keccak-256"
    )

    abi_path = Path.join([root, "contracts", entry["abi_path"]])

    assert_equal!(
      :crypto.hash(:sha256, File.read!(abi_path)) |> Base.encode16(case: :lower),
      entry["abi_sha256"],
      "Multicall3 ABI digest"
    )

    [read] = entry["reads"]

    selector =
      cast!(cast, ["sig", read["signature"]], "aggregate3 selector") |> String.downcase()

    assert_equal!(selector, read["selector"], "aggregate3 selector")

    runtime_selectors =
      cast!(cast, ["selectors", code], "Multicall3 selectors")
      |> String.split("\n", trim: true)
      |> Enum.map(fn line -> line |> String.split() |> hd() |> String.downcase() end)
      |> MapSet.new()

    unless MapSet.member?(runtime_selectors, selector) do
      Mix.raise("the deployed Multicall3 runtime does not declare #{read["signature"]}")
    end

    # It is identified, and it is never prepared against.
    assert_equal!(entry["action_ids"], [], "Multicall3 prepared actions")
  end

  defp verify_staking!(cast, rpc_url, historical_rpc_url, root, manifest) do
    Mix.shell().info("Verifying Regent staking deployment and reads...")
    contracts = manifest["contracts"]
    staking = contracts["regent_revenue_staking"]

    verify_runtime!(cast, rpc_url, "regent_revenue_staking", staking)
    verify_deployment!(cast, historical_rpc_url, "regent_revenue_staking", staking)
    verify_abi_selectors!(cast, rpc_url, root, "regent_revenue_staking", staking)
    verify_staking_getters!(cast, rpc_url, manifest)
  end

  defp verify_redemption!(cast, rpc_url, historical_rpc_url, root, manifest) do
    Mix.shell().info("Verifying Animata redemption deployments and reads...")
    contracts = manifest["contracts"]

    for id <- ["animata_redeemer", "animata_i", "animata_ii", "base_usdc"] do
      verify_runtime!(cast, rpc_url, id, contracts[id])
    end

    for id <- ["animata_redeemer", "animata_i", "animata_ii"] do
      verify_deployment!(cast, historical_rpc_url, id, contracts[id])
    end

    verify_abi_selectors!(cast, rpc_url, root, "animata_redeemer", contracts["animata_redeemer"])
    verify_redeemer_getters!(cast, rpc_url, manifest)
    verify_redemption_approval_interfaces!(cast, rpc_url, manifest)
    verify_redemption_rejections!(cast, rpc_url, manifest)
  end

  defp verify_runtime!(cast, rpc_url, id, contract) do
    code = cast!(cast, ["code", contract["address"], "--rpc-url", rpc_url], "#{id} runtime")

    if code == "0x" do
      Mix.raise("#{id} has no deployed runtime code")
    end

    bytes = code |> String.trim_leading("0x") |> Base.decode16!(case: :mixed)
    expected = contract["runtime_code"]

    assert_equal!(byte_size(bytes), expected["bytes"], "#{id} runtime byte length")

    sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    assert_equal!(sha256, expected["sha256"], "#{id} runtime SHA-256")

    keccak = cast!(cast, ["keccak", code], "#{id} runtime Keccak-256")
    assert_equal!(String.downcase(keccak), expected["keccak256"], "#{id} runtime Keccak-256")
  end

  defp verify_deployment!(cast, rpc_url, id, contract) do
    receipt =
      cast!(
        cast,
        ["receipt", contract["deployment_transaction"], "--json", "--rpc-url", rpc_url],
        "#{id} deployment receipt"
      )
      |> Jason.decode!()

    assert_address!(receipt["contractAddress"], contract["address"], "#{id} deployment receipt")
    assert_equal!(receipt["status"], "0x1", "#{id} deployment status")
  end

  defp verify_abi_selectors!(cast, rpc_url, root, id, contract) do
    code = cast!(cast, ["code", contract["address"], "--rpc-url", rpc_url], "#{id} selectors")

    runtime_selectors =
      cast!(cast, ["selectors", code], "#{id} selectors")
      |> String.split("\n", trim: true)
      |> Enum.map(fn line -> line |> String.split() |> hd() |> String.downcase() end)
      |> MapSet.new()

    abi_selectors =
      root
      |> Path.join("contracts")
      |> Path.join(contract["abi"]["path"])
      |> read_json!()
      |> Enum.filter(&(&1["type"] == "function"))
      |> Enum.map(fn item ->
        signature = canonical_signature(item)
        cast!(cast, ["sig", signature], "#{id} ABI selector")
      end)
      |> Enum.map(&String.downcase/1)
      |> MapSet.new()

    assert_equal!(abi_selectors, runtime_selectors, "#{id} ABI/runtime selector set")

    if id == "animata_redeemer" do
      verify_redeem_with_permit_dispatch!(cast, rpc_url, contract)
    end
  end

  @doc false
  def canonical_signature(%{"name" => name, "inputs" => inputs}) do
    types = Enum.map_join(inputs, ",", &canonical_abi_type/1)
    "#{name}(#{types})"
  end

  defp canonical_abi_type(%{"type" => "tuple" <> suffix, "components" => components}) do
    "(#{Enum.map_join(components, ",", &canonical_abi_type/1)})#{suffix}"
  end

  defp canonical_abi_type(%{"type" => type}), do: type

  defp verify_redeem_with_permit_dispatch!(cast, rpc_url, contract) do
    zero = @zero_address

    calldata =
      cast!(
        cast,
        [
          "calldata",
          "redeemWithPermit(address,uint256,((address,uint256),uint256,uint256),bytes)",
          zero,
          "1",
          "((#{zero},0),0,0)",
          "0x"
        ],
        "redeemWithPermit calldata"
      )

    revert =
      cast_failure!(
        cast,
        ["call", contract["address"], calldata, "--rpc-url", rpc_url],
        "redeemWithPermit dispatch"
      )

    unless String.contains?(revert, "token != USDC") do
      Mix.raise("redeemWithPermit canonical selector did not reach the verified function")
    end
  end

  defp verify_staking_getters!(cast, rpc_url, manifest) do
    staking = manifest["contracts"]["regent_revenue_staking"]
    expected = staking["onchain_constants"]
    address = staking["address"]

    assert_address!(
      call_one!(cast, rpc_url, address, "stakeToken()(address)"),
      expected["stake_token"],
      "staking token"
    )

    assert_address!(
      call_one!(cast, rpc_url, address, "usdc()(address)"),
      expected["usdc"],
      "staking USDC"
    )

    paused = call_one!(cast, rpc_url, address, "paused()(bool)")
    unless is_boolean(paused), do: Mix.raise("staking paused() returned a non-boolean value")

    total_staked =
      call_one!(cast, rpc_url, address, "totalStaked()(uint256)")
      |> integer_value!("totalStaked()")

    unless total_staked >= 0, do: Mix.raise("invalid totalStaked()")

    for signature <- [
          "stakedBalance(address)(uint256)",
          "previewClaimableUSDC(address)(uint256)",
          "previewClaimableRegent(address)(uint256)",
          "previewFundedClaimableRegent(address)(uint256)"
        ] do
      actual = call_one!(cast, rpc_url, address, signature, [@zero_address])
      assert_equal!(integer_value!(actual, signature), 0, signature)
    end

    assert_equal!(
      call_one!(cast, rpc_url, expected["stake_token"], "balanceOf(address)(uint256)", [
        @zero_address
      ])
      |> integer_value!("staking token balanceOf"),
      0,
      "staking token balanceOf"
    )

    assert_equal!(
      call_one!(cast, rpc_url, expected["stake_token"], "allowance(address,address)(uint256)", [
        @zero_address,
        address
      ])
      |> integer_value!("staking token allowance"),
      0,
      "staking token allowance"
    )
  end

  defp verify_redeemer_getters!(cast, rpc_url, manifest) do
    contracts = manifest["contracts"]
    redeemer = contracts["animata_redeemer"]
    expected = redeemer["onchain_constants"]
    address = redeemer["address"]

    for {label, signature, key} <- [
          {"Animata I", "COLL1()(address)", "animata_i"},
          {"Animata II", "COLL2()(address)", "animata_ii"},
          {"result collection", "COLL3()(address)", "result_collection"},
          {"redemption USDC", "USDC()(address)", "usdc"},
          {"redemption REGENT", "REGENT()(address)", "regent"}
        ] do
      assert_address!(call_one!(cast, rpc_url, address, signature), expected[key], label)
    end

    for {label, signature, key} <- [
          {"USDC_PRICE", "USDC_PRICE()(uint256)", "usdc_price_atomic"},
          {"price", "price()(uint256)", "usdc_price_atomic"},
          {"REGENT_PAYOUT", "REGENT_PAYOUT()(uint256)", "regent_payout_atomic"},
          {"VEST_DURATION", "VEST_DURATION()(uint256)", "vest_duration_seconds"},
          {"MAX_ID", "MAX_ID()(uint256)", "max_source_token_id"}
        ] do
      actual = call_one!(cast, rpc_url, address, signature) |> to_string()
      assert_equal!(actual, to_string(expected[key]), label)
    end

    assert_equal!(
      call_one!(cast, rpc_url, expected["usdc"], "decimals()(uint8)")
      |> integer_value!("Base USDC decimals"),
      6,
      "Base USDC decimals"
    )

    assert_equal!(
      call_one!(cast, rpc_url, address, "claimable(address)(uint256)", [@zero_address])
      |> integer_value!("claimable"),
      0,
      "claimable"
    )

    assert_equal!(
      call_values!(cast, rpc_url, address, "getVest(address)(uint128,uint128,uint128,uint64)", [
        @zero_address
      ])
      |> Enum.map(&integer_value!(&1, "empty vest")),
      [0, 0, 0, 0],
      "empty vest"
    )

    for {collection, token_id, result_id} <- [
          {expected["animata_i"], 1, 1},
          {expected["animata_i"], 999, 999},
          {expected["animata_ii"], 1, 1000},
          {expected["animata_ii"], 999, 1998}
        ] do
      assert_equal!(
        call_one!(cast, rpc_url, address, "mapToCollection3(address,uint256)(uint256)", [
          collection,
          to_string(token_id)
        ])
        |> integer_value!("result token mapping"),
        result_id,
        "result token mapping"
      )
    end
  end

  defp verify_redemption_approval_interfaces!(cast, rpc_url, manifest) do
    contracts = manifest["contracts"]
    redeemer = contracts["animata_redeemer"]["address"]

    for id <- ["animata_i", "animata_ii"] do
      collection = contracts[id]["address"]

      assert_equal!(
        call_one!(cast, rpc_url, collection, "supportsInterface(bytes4)(bool)", ["0x80ac58cd"]),
        true,
        "#{id} ERC-721 interface"
      )

      approved =
        call_one!(cast, rpc_url, collection, "isApprovedForAll(address,address)(bool)", [
          @probe_address,
          redeemer
        ])

      unless is_boolean(approved), do: Mix.raise("#{id} approval read returned a non-boolean")

      output =
        simulate_call!(
          cast,
          rpc_url,
          collection,
          "setApprovalForAll(address,bool)",
          [redeemer, "true"],
          @probe_address,
          "#{id} setApprovalForAll"
        )

      assert_equal!(output, "0x", "#{id} setApprovalForAll result")

      assert_revert_contains!(
        cast,
        rpc_url,
        collection,
        "ownerOf(uint256)(address)",
        ["0"],
        "0xdf2d9b42",
        "#{id} ownerOf dispatch"
      )
    end

    usdc = contracts["base_usdc"]["address"]

    for {label, signature, args} <- [
          {"Base USDC balance", "balanceOf(address)(uint256)", [@probe_address]},
          {"Base USDC allowance", "allowance(address,address)(uint256)",
           [
             @probe_address,
             redeemer
           ]}
        ] do
      value = call_one!(cast, rpc_url, usdc, signature, args) |> integer_value!(label)
      unless value >= 0, do: Mix.raise("#{label} returned a negative value")
    end

    assert_equal!(
      simulate_call!(
        cast,
        rpc_url,
        usdc,
        "approve(address,uint256)(bool)",
        [redeemer, "0"],
        @probe_address,
        "Base USDC exact approval"
      )
      |> Jason.decode!(),
      [true],
      "Base USDC exact approval"
    )
  end

  defp verify_redemption_rejections!(cast, rpc_url, manifest) do
    contracts = manifest["contracts"]
    redeemer = contracts["animata_redeemer"]
    address = redeemer["address"]
    expected = redeemer["onchain_constants"]

    for token_id <- ["0", "1000"] do
      assert_revert_contains!(
        cast,
        rpc_url,
        address,
        "mapToCollection3(address,uint256)(uint256)",
        [expected["animata_i"], token_id],
        "id",
        "redemption token-id boundary"
      )
    end

    assert_revert_contains!(
      cast,
      rpc_url,
      address,
      "mapToCollection3(address,uint256)(uint256)",
      [expected["result_collection"], "1"],
      "invalid collection",
      "redemption result-collection rejection"
    )
  end

  defp call_one!(cast, rpc_url, address, signature, call_args \\ []) do
    case call_values!(cast, rpc_url, address, signature, call_args) do
      [value] -> value
      values -> Mix.raise("Unexpected result shape for #{signature}: #{length(values)} values")
    end
  end

  defp call_values!(cast, rpc_url, address, signature, call_args) do
    args = ["call", address, signature] ++ call_args ++ ["--json", "--rpc-url", rpc_url]
    cast!(cast, args, signature) |> Jason.decode!()
  end

  defp simulate_call!(cast, rpc_url, address, signature, call_args, from, label) do
    args =
      ["call", address, signature] ++
        call_args ++ ["--from", from, "--json", "--rpc-url", rpc_url]

    cast!(cast, args, label)
  end

  defp assert_revert_contains!(cast, rpc_url, address, signature, call_args, marker, label) do
    args = ["call", address, signature] ++ call_args ++ ["--json", "--rpc-url", rpc_url]
    revert = cast_failure!(cast, args, label)

    unless String.contains?(revert, marker) do
      Mix.raise("#{label} did not return the expected verified rejection")
    end
  end

  defp cast!(cast, args, label), do: cast_attempt(cast, args, label, 1)

  defp cast_failure!(cast, args, label) do
    task = Task.async(fn -> System.cmd(cast, args, stderr_to_stdout: true) end)
    result = Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill)

    case result do
      {:ok, {output, status}} when status != 0 -> output
      {:ok, {_output, 0}} -> Mix.raise("#{label} unexpectedly succeeded")
      nil -> Mix.raise("#{label} timed out")
    end
  end

  defp cast_attempt(cast, args, label, attempt) do
    task = Task.async(fn -> System.cmd(cast, args, stderr_to_stdout: true) end)

    result = Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill)

    case result do
      {:ok, {output, 0}} ->
        String.trim(output)

      {:ok, {output, _status}} when attempt < @attempts ->
        if transient_failure?(output) do
          Process.sleep(250 * attempt)
          cast_attempt(cast, args, label, attempt + 1)
        else
          Mix.raise("#{label} failed (provider details redacted)")
        end

      nil when attempt < @attempts ->
        Process.sleep(250 * attempt)
        cast_attempt(cast, args, label, attempt + 1)

      {:exit, _reason} when attempt < @attempts ->
        Process.sleep(250 * attempt)
        cast_attempt(cast, args, label, attempt + 1)

      _ ->
        Mix.raise(
          "#{label} failed after #{@attempts} bounded attempts (provider details redacted)"
        )
    end
  end

  defp transient_failure?(output) do
    normalized = String.downcase(output)

    Enum.any?(
      ["429", "rate limit", "timeout", "timed out", "connection", "temporarily"],
      &String.contains?(normalized, &1)
    )
  end

  defp find_cast! do
    [Path.join(System.user_home!(), ".foundry/bin/cast"), System.find_executable("cast")]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.find(fn candidate ->
      File.regular?(candidate) and
        match?({"cast Version: 1.5.1-stable" <> _, 0}, System.cmd(candidate, ["--version"]))
    end)
    |> case do
      nil -> Mix.raise("Foundry cast 1.5.1-stable is required")
      cast -> cast
    end
  end

  defp integer_value!(value, _label) when is_integer(value), do: value

  defp integer_value!(value, label) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> Mix.raise("#{label} returned a non-integer value")
    end
  end

  defp integer_value!(_value, label), do: Mix.raise("#{label} returned a non-integer value")

  defp assert_address!(actual, expected, label) do
    assert_equal!(String.downcase(actual), String.downcase(expected), label)
  end

  defp assert_equal!(actual, expected, label) do
    unless actual == expected do
      Mix.raise("#{label} drifted: expected #{inspect(expected)}, got #{inspect(actual)}")
    end
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
