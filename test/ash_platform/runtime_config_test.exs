defmodule AshPlatform.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../config/runtime.exs", __DIR__)

  setup do
    names = [
      "PRIVY_APP_ID",
      "PRIVY_VERIFICATION_KEY",
      "REGENT_ADMIN_WALLET_ADDRESSES",
      "DATABASE_POOLED_URL",
      "DATABASE_DIRECT_URL",
      "DATABASE_URL",
      "ASH_PLATFORM_DATABASE_CLUSTER_ID",
      "ASH_PLATFORM_DATABASE_CLUSTER_NAME",
      "ASH_PLATFORM_DATABASE_TARGET_MODE",
      "ASH_PLATFORM_RELEASE_COMMAND",
      "FLY_APP_NAME",
      "PHX_HOST",
      "PORT",
      "SECRET_KEY_BASE",
      "ASH_PLATFORM_APP_SURFACES",
      "ASH_PLATFORM_AUTOLAUNCH_SURFACES",
      "ASH_PLATFORM_AUTOLAUNCH_LAB_CONFIG",
      "ASH_PLATFORM_ACCEPTANCE_RUN_ID",
      "AUTOLAUNCH_INDEXER_RPC_URL",
      "BASE_READ_RPC_URL",
      "OPENSEA_API_KEY"
    ]

    previous = Map.new(names, &{&1, System.get_env(&1)})
    previous_verifier = Application.get_env(:ash_platform, :acceptance_ownership_verifier)
    Enum.each(names, &System.delete_env/1)

    Application.put_env(
      :ash_platform,
      :acceptance_ownership_verifier,
      fn _config, _run_id -> :ok end
    )

    # Production demands an explicit gate setting; these tests cover the rest of the file.
    System.put_env("ASH_PLATFORM_APP_SURFACES", "on")

    on_exit(fn ->
      Enum.each(previous, fn {name, value} -> restore_env(name, value) end)

      if is_nil(previous_verifier) do
        Application.delete_env(:ash_platform, :acceptance_ownership_verifier)
      else
        Application.put_env(:ash_platform, :acceptance_ownership_verifier, previous_verifier)
      end
    end)

    :ok
  end

  test "Privy verification key accepts secret-manager-safe escaped PEM newlines" do
    System.put_env("PRIVY_APP_ID", "local-privy-app")

    System.put_env(
      "PRIVY_VERIFICATION_KEY",
      "-----BEGIN PUBLIC KEY-----\\r\\nabc123\\n-----END PUBLIC KEY-----"
    )

    assert privy_config() == [
             app_id: "local-privy-app",
             verification_key: "-----BEGIN PUBLIC KEY-----\nabc123\n-----END PUBLIC KEY-----"
           ]
  end

  test "Privy verification key preserves a native multiline PEM" do
    pem = "-----BEGIN PUBLIC KEY-----\nabc123\n-----END PUBLIC KEY-----"
    System.put_env("PRIVY_APP_ID", "local-privy-app")
    System.put_env("PRIVY_VERIFICATION_KEY", pem)

    assert privy_config() == [app_id: "local-privy-app", verification_key: pem]
  end

  test "comment moderation accepts a comma-separated admin wallet allowlist" do
    System.put_env(
      "REGENT_ADMIN_WALLET_ADDRESSES",
      " 0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222 "
    )

    assert runtime_config(:admin_wallet_addresses) == [
             "0x1111111111111111111111111111111111111111",
             "0x2222222222222222222222222222222222222222"
           ]
  end

  test "OpenSea key is server-only runtime config and does not replace the test client key" do
    System.put_env("OPENSEA_API_KEY", "server-secret")

    assert runtime_config(:opensea_api_key) == "server-secret"
    assert get_in(read_runtime_config(:test), [:ash_platform, :opensea_api_key]) == nil
    refute File.read!("assets/js/app.ts") =~ "OPENSEA_API_KEY"
  end

  test "test runtime keeps its fixed local repository despite database environment values" do
    System.put_env("DATABASE_POOLED_URL", "postgresql://pooled:secret@remote.test/db")
    System.put_env("DATABASE_DIRECT_URL", "postgresql://direct:secret@remote.test/db")
    System.put_env("DATABASE_URL", "postgresql://legacy:secret@remote.test/db")

    assert runtime_repo_config(:test) == nil

    test_repo =
      "config/test.exs"
      |> Config.Reader.read!(env: :test, target: :host)
      |> get_in([:ash_platform, AshPlatform.Repo])

    assert Keyword.take(test_repo, [:hostname, :port, :database]) == [
             hostname: "127.0.0.1",
             port: 5432,
             database: "ash_platform_test"
           ]
  end

  test "production runtime enables the repository with pooled access" do
    System.put_env("BASE_READ_RPC_URL", "https://base.example.test")
    pooled = "postgresql://pooled:secret@pool.example.test/ash_platform"
    System.put_env("DATABASE_POOLED_URL", pooled)
    System.put_env("DATABASE_DIRECT_URL", "postgresql://direct:secret@direct.example.test/db")
    System.put_env("PHX_HOST", "shadow.example.test")
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))

    config = read_runtime_config(:prod)

    assert get_in(config, [:ash_platform, :database_startup_enabled])

    assert get_in(config, [:ash_platform, AshPlatform.Repo]) == [
             url: pooled,
             socket_options: [:inet6]
           ]

    endpoint = get_in(config, [:ash_platform, AshPlatformWeb.Endpoint])

    assert endpoint[:server]
    assert endpoint[:secret_key_base] == String.duplicate("s", 64)
    assert endpoint[:url][:host] == "shadow.example.test"
    assert endpoint[:url][:scheme] == "https"
    assert endpoint[:http][:port] == 4000
    assert endpoint[:http][:ip] == {0, 0, 0, 0, 0, 0, 0, 0}
  end

  test "PKG-RUNTIME serving uses the host without its surrounding whitespace" do
    System.put_env("BASE_READ_RPC_URL", "https://base.example.test")

    System.put_env(
      "DATABASE_POOLED_URL",
      "postgresql://pooled:secret@pool.example.test/ash_platform"
    )

    System.put_env("PHX_HOST", "  shadow.example.test\n")
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))

    config = read_runtime_config(:prod)

    assert get_in(config, [:ash_platform, AshPlatformWeb.Endpoint])[:url][:host] ==
             "shadow.example.test"
  end

  test "production runtime fails closed without pooled access" do
    assert_raise RuntimeError, "DATABASE_POOLED_URL is required", fn ->
      read_runtime_config(:prod)
    end
  end

  test "migration runtime selects direct access only for the exact rehearsal target" do
    System.put_env("BASE_READ_RPC_URL", "https://base.example.test")
    direct = "postgresql://direct:secret@direct.example.test/ash_platform"
    System.put_env("ASH_PLATFORM_RELEASE_COMMAND", "migrate")
    System.put_env("ASH_PLATFORM_DATABASE_TARGET_MODE", "rehearsal")
    System.put_env("ASH_PLATFORM_DATABASE_CLUSTER_ID", "nvwq9ozp9ye03kl1")
    System.put_env("ASH_PLATFORM_DATABASE_CLUSTER_NAME", "regents-pg-test")
    System.put_env("DATABASE_DIRECT_URL", direct)

    assert runtime_repo_config(:prod) == [url: direct, socket_options: [:inet6]]
  end

  test "migration runtime rejects an arbitrary direct URL without rehearsal identity" do
    System.put_env("ASH_PLATFORM_RELEASE_COMMAND", "migrate")
    System.put_env("DATABASE_DIRECT_URL", "postgresql://direct:secret@direct.example.test/db")

    assert_raise RuntimeError,
                 "database migration requires rehearsal mode for cluster nvwq9ozp9ye03kl1 named regents-pg-test",
                 fn -> runtime_repo_config(:prod) end
  end

  test "migration runtime refuses production mode before reading direct access" do
    System.put_env("ASH_PLATFORM_RELEASE_COMMAND", "migrate")
    System.put_env("ASH_PLATFORM_DATABASE_TARGET_MODE", "production")

    assert_raise RuntimeError,
                 "production migration requires separate Chief-authorized production migration configuration",
                 fn -> runtime_repo_config(:prod) end
  end

  test "PKG-RUNTIME serving fails closed without a host" do
    put_pooled_url()

    assert_raise System.EnvError, ~r/PHX_HOST/, fn -> read_runtime_config(:prod) end
  end

  test "PKG-RUNTIME serving fails closed on a blank host" do
    put_pooled_url()
    System.put_env("PHX_HOST", " ")
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))

    assert_raise RuntimeError, "PHX_HOST must not be empty", fn ->
      read_runtime_config(:prod)
    end
  end

  test "PKG-RUNTIME serving fails closed without a session secret" do
    put_pooled_url()
    System.put_env("PHX_HOST", "shadow.example.test")

    assert_raise System.EnvError, ~r/SECRET_KEY_BASE/, fn -> read_runtime_config(:prod) end
  end

  test "PKG-RUNTIME serving fails closed on an undersized session secret" do
    put_pooled_url()
    System.put_env("PHX_HOST", "shadow.example.test")
    System.put_env("SECRET_KEY_BASE", "too-short")

    assert_raise RuntimeError, "SECRET_KEY_BASE must be at least 64 bytes", fn ->
      read_runtime_config(:prod)
    end
  end

  test "PKG-RUNTIME migration startup does not require serving-only endpoint values" do
    System.put_env("BASE_READ_RPC_URL", "https://base.example.test")
    direct = "postgresql://direct:secret@direct.example.test/ash_platform"
    System.put_env("ASH_PLATFORM_RELEASE_COMMAND", "migrate")
    System.put_env("ASH_PLATFORM_DATABASE_TARGET_MODE", "rehearsal")
    System.put_env("ASH_PLATFORM_DATABASE_CLUSTER_ID", "nvwq9ozp9ye03kl1")
    System.put_env("ASH_PLATFORM_DATABASE_CLUSTER_NAME", "regents-pg-test")
    System.put_env("DATABASE_DIRECT_URL", direct)

    config = read_runtime_config(:prod)

    assert get_in(config, [:ash_platform, AshPlatform.Repo]) == [
             url: direct,
             socket_options: [:inet6]
           ]

    assert get_in(config, [:ash_platform, AshPlatformWeb.Endpoint]) == nil
  end

  # Production must name the Base endpoint it trusts, so every production-path
  # case here supplies one and one case proves the boot without it.
  test "PKG-RUNTIME production fails closed without a Base read endpoint" do
    put_pooled_url()
    System.put_env("PHX_HOST", "shadow.example.test")
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))
    System.delete_env("BASE_READ_RPC_URL")

    assert_raise System.EnvError, ~r/BASE_READ_RPC_URL/, fn -> read_runtime_config(:prod) end
  end

  test "PKG-RUNTIME development keeps its default Base read endpoint" do
    assert get_in(read_runtime_config(:dev), [:ash_platform, :base_read_rpc_url]) == nil

    assert "config/config.exs"
           |> Config.Reader.read!(env: :dev, target: :host)
           |> get_in([:ash_platform, :base_read_rpc_url]) == "https://base-rpc.publicnode.com"
  end

  test "Autolaunch surfaces open by default only under test, and otherwise only on an exact on" do
    put_pooled_url()
    System.put_env("PHX_HOST", "shadow.example.test")
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))

    assert autolaunch_surfaces?(:test)
    refute autolaunch_surfaces?(:dev)
    refute autolaunch_surfaces?(:prod)

    System.put_env("ASH_PLATFORM_AUTOLAUNCH_SURFACES", "on")
    assert Enum.all?([:test, :dev, :prod], &autolaunch_surfaces?/1)

    for setting <- ["off", "ON", "true", ""] do
      System.put_env("ASH_PLATFORM_AUTOLAUNCH_SURFACES", setting)
      refute Enum.any?([:test, :dev, :prod], &autolaunch_surfaces?/1)
    end
  end

  test "the local Autolaunch lab is development/test only and disables the production indexer",
       context do
    path = write_lab_config!(context)
    System.put_env("ASH_PLATFORM_AUTOLAUNCH_LAB_CONFIG", path)
    System.put_env("ASH_PLATFORM_ACCEPTANCE_RUN_ID", "local_lab_runtime_1")
    System.put_env("AUTOLAUNCH_INDEXER_RPC_URL", "https://indexer.example.test/private")

    for environment <- [:dev, :test] do
      config = read_runtime_config(environment)

      assert get_in(config, [:ash_platform, :autolaunch_lab_enabled])
      assert get_in(config, [:ash_platform, :autolaunch_lab_config_path]) == path
      assert get_in(config, [:ash_platform, :autolaunch_indexer_rpc_url]) == nil

      assert get_in(config, [:ash_platform, AshPlatform.Repo])[:database] ==
               "ash_platform_acceptance_local_lab_runtime_1"
    end

    assert_raise RuntimeError,
                 "ASH_PLATFORM_AUTOLAUNCH_LAB_CONFIG is development/test only",
                 fn -> read_runtime_config(:prod) end
  end

  test "a configured local lab fails boot on a missing or malformed config", context do
    missing = Path.join(System.tmp_dir!(), "missing-lab-#{context.test}.json")
    System.put_env("ASH_PLATFORM_AUTOLAUNCH_LAB_CONFIG", missing)
    System.put_env("ASH_PLATFORM_ACCEPTANCE_RUN_ID", "local_lab_runtime_2")

    assert_raise RuntimeError, ~r/configuration is invalid: missing_file/, fn ->
      read_runtime_config(:dev)
    end

    path = Path.join(System.tmp_dir!(), "bad-lab-#{context.test}.json")
    File.write!(path, ~s({"rpc_url":"http://127.0.0.1:8545","chain_id":8453}))
    on_exit(fn -> File.rm(path) end)
    System.put_env("ASH_PLATFORM_AUTOLAUNCH_LAB_CONFIG", path)

    assert_raise RuntimeError, ~r/configuration is invalid/, fn -> read_runtime_config(:dev) end
  end

  test "a configured local lab fails boot before serving when ownership cannot be proved",
       context do
    path = write_lab_config!(context)
    System.put_env("ASH_PLATFORM_AUTOLAUNCH_LAB_CONFIG", path)
    System.put_env("ASH_PLATFORM_ACCEPTANCE_RUN_ID", "unowned_runtime")

    Application.put_env(
      :ash_platform,
      :acceptance_ownership_verifier,
      fn _config, _run_id -> raise "local acceptance database ownership marker mismatch" end
    )

    assert_raise RuntimeError, "local acceptance database ownership marker mismatch", fn ->
      read_runtime_config(:dev)
    end
  end

  defp autolaunch_surfaces?(environment),
    do: get_in(read_runtime_config(environment), [:ash_platform, :autolaunch_surfaces])

  defp put_pooled_url do
    System.put_env("BASE_READ_RPC_URL", "https://base.example.test")

    System.put_env(
      "DATABASE_POOLED_URL",
      "postgresql://pooled:secret@pool.example.test/ash_platform"
    )
  end

  defp privy_config do
    runtime_config(:privy)
  end

  defp runtime_config(key) when is_atom(key) do
    read_runtime_config(:dev)
    |> get_in([:ash_platform, key])
  end

  defp read_runtime_config(environment) do
    @runtime_config
    |> Config.Reader.read!(env: environment, target: :host)
  end

  defp runtime_repo_config(environment),
    do: get_in(read_runtime_config(environment), [:ash_platform, AshPlatform.Repo])

  defp write_lab_config!(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "runtime-lab-#{context.test |> :erlang.phash2() |> Integer.to_string()}.json"
      )

    addresses =
      ~w(
        cca_factory escrow_implementation factory governance_safe hook permit2 pool_manager
        position_manager receiver_implementation regent splitter_implementation strategy
        uerc20_factory
      )
      |> Map.new(&{&1, "0x1111111111111111111111111111111111111111"})

    abis =
      ~w(auction escrow factory hook permit2 receiver splitter strategy token)
      |> Map.new(fn name ->
        entries =
          AshPlatform.Autolaunch.LabAbi.requirements()
          |> Map.get(name, [])
          |> Enum.map(&lab_abi_entry/1)

        {name, if(entries == [], do: [lab_abi_entry("placeholder()")], else: entries)}
      end)

    File.write!(
      path,
      Jason.encode!(%{
        "rpc_url" => "http://127.0.0.1:49713",
        "chain_id" => 31_337,
        "addresses" => addresses,
        "abis" => abis
      })
    )

    on_exit(fn -> File.rm(path) end)
    path
  end

  defp lab_abi_entry({:f, {signature, mutability, outputs}}) do
    {name, inputs} = signature_parts(signature)

    %{
      "type" => "function",
      "name" => name,
      "inputs" => lab_abi_types(inputs),
      "outputs" => Enum.flat_map(outputs, &lab_abi_types/1),
      "stateMutability" => mutability
    }
  end

  defp lab_abi_entry({:e, {signature, indexed}}) do
    {name, inputs} = signature_parts(signature)

    inputs =
      inputs
      |> lab_abi_types()
      |> Enum.zip(indexed)
      |> Enum.map(fn {input, indexed?} -> Map.put(input, "indexed", indexed?) end)

    %{"type" => "event", "name" => name, "inputs" => inputs, "anonymous" => false}
  end

  defp lab_abi_entry(signature) when is_binary(signature),
    do: lab_abi_entry({:f, {signature, "nonpayable", []}})

  defp signature_parts(signature) do
    [name, inputs] =
      Regex.run(~r/\A([^()]+)\((.*)\)\z/, signature, capture: :all_but_first)

    {name, inputs}
  end

  defp lab_abi_types(""), do: []

  defp lab_abi_types(arguments) do
    arguments
    |> split_lab_types()
    |> Enum.map(fn
      "(" <> tuple ->
        %{
          "type" => "tuple",
          "name" => "",
          "components" => tuple |> String.trim_trailing(")") |> lab_abi_types()
        }

      type ->
        %{"type" => type, "name" => ""}
    end)
  end

  defp split_lab_types(value) do
    {parts, current, _depth} =
      value
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        "(", {parts, current, depth} -> {parts, current <> "(", depth + 1}
        ")", {parts, current, depth} -> {parts, current <> ")", depth - 1}
        ",", {parts, current, 0} -> {[current | parts], "", 0}
        char, {parts, current, depth} -> {parts, current <> char, depth}
      end)

    Enum.reverse([current | parts])
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
