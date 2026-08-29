defmodule AshPlatform.DatabaseConfig do
  @moduledoc false

  @cluster_id "nvwq9ozp9ye03kl1"
  @cluster_name "regents-pg-test"
  @production_identities ["regents-platform-prod", "platform-phx"]
  @rehearsal_target_error "database migration requires rehearsal mode for cluster nvwq9ozp9ye03kl1 named regents-pg-test"
  @production_migration_error "production migration requires separate Chief-authorized production migration configuration"

  def runtime_config!(environment, getenv \\ &System.get_env/1)

  def runtime_config!(:test, getenv), do: local_or_acceptance_config!(:test, getenv)

  def runtime_config!(:prod, getenv) do
    database_url!(getenv, "DATABASE_POOLED_URL")
  end

  def runtime_config!(:dev, getenv) do
    if present?(getenv.("ASH_PLATFORM_AUTOLAUNCH_LAB_CONFIG")) do
      acceptance_config!(:dev, getenv)
    else
      case remote_target(getenv) do
        :local -> local_config(getenv)
        :remote -> database_url!(getenv, "DATABASE_POOLED_URL")
      end
    end
  end

  def runtime_config!(_environment, _getenv), do: nil

  def release_config!(getenv \\ &System.get_env/1) do
    require_rehearsal_target!(getenv)
    database_url!(getenv, "DATABASE_DIRECT_URL")
  end

  @doc false
  def verify_acceptance_ownership!(
        environment,
        config,
        getenv \\ &System.get_env/1,
        verifier \\ nil
      )

  def verify_acceptance_ownership!(environment, config, getenv, verifier)
      when environment in [:dev, :test] and is_list(config) do
    run_id = getenv.("ASH_PLATFORM_ACCEPTANCE_RUN_ID")
    username = getenv.("USER")

    unless present?(run_id) and present?(username) do
      raise "Autolaunch lab requires ASH_PLATFORM_ACCEPTANCE_RUN_ID and USER"
    end

    AshPlatform.LocalDatabaseFixture.reject_remote_environment!(
      Map.new(
        ~w(DATABASE_URL DATABASE_DIRECT_URL DATABASE_POOLED_URL FLY_APP_NAME FLY_REGION),
        &{&1, getenv.(&1)}
      )
    )

    AshPlatform.LocalDatabaseFixture.validate_acceptance_target!(:test, config, username)

    if to_string(config[:database]) != "ash_platform_acceptance_#{run_id}" do
      raise "local acceptance fixture refused mismatched run database target"
    end

    (verifier || (&AshPlatform.LocalDatabaseFixture.PostgresAdapter.verify_owned!/2)).(
      config,
      run_id
    )
  end

  def verify_acceptance_ownership!(_environment, _config, _getenv, _verifier),
    do: raise("Autolaunch lab database is development/test only")

  defp database_url!(getenv, variable) do
    with value when is_binary(value) and value != "" <- getenv.(variable),
         {:ok, %URI{scheme: scheme, host: host, path: "/" <> database, userinfo: userinfo} = uri} <-
           parse_uri(value),
         true <- scheme in ["postgres", "postgresql"],
         true <- present?(host),
         true <- present?(database),
         true <- valid_userinfo?(userinfo),
         false <- production_identity?(uri) do
      # Connections traverse Fly's WireGuard-encrypted private network, where managed Postgres
      # publishes only an AAAA record, so resolve over IPv6. TLS is not used because OTP 28 cannot
      # decode the managed-Postgres certificate (asn1 bad_range), matching the platform-standard
      # in-network posture; revisit if the endpoint ever leaves the private network.
      [url: value, socket_options: [:inet6]]
    else
      nil -> raise "#{variable} is required"
      "" -> raise "#{variable} is required"
      _ -> raise "#{variable} must be a valid PostgreSQL URL for the approved target"
    end
  end

  defp parse_uri(value) do
    with {:ok, uri} <- URI.new(value) do
      Ecto.Repo.Supervisor.parse_url(value)
      {:ok, uri}
    end
  rescue
    _error -> :error
  end

  defp remote_target(getenv) do
    cluster_id = getenv.("ASH_PLATFORM_DATABASE_CLUSTER_ID")
    cluster_name = getenv.("ASH_PLATFORM_DATABASE_CLUSTER_NAME")
    fly_app_name = getenv.("FLY_APP_NAME")

    cond do
      production_identity?(fly_app_name) ->
        raise remote_target_error()

      is_nil(cluster_id) and is_nil(cluster_name) ->
        :local

      cluster_id == @cluster_id and cluster_name == @cluster_name ->
        :remote

      true ->
        raise remote_target_error()
    end
  end

  defp require_rehearsal_target!(getenv) do
    mode = getenv.("ASH_PLATFORM_DATABASE_TARGET_MODE")

    cond do
      mode == "production" ->
        raise @production_migration_error

      mode == "rehearsal" and
        getenv.("ASH_PLATFORM_DATABASE_CLUSTER_ID") == @cluster_id and
        getenv.("ASH_PLATFORM_DATABASE_CLUSTER_NAME") == @cluster_name and
          not production_identity?(getenv.("FLY_APP_NAME")) ->
        :ok

      true ->
        raise @rehearsal_target_error
    end
  end

  defp local_config(getenv) do
    [
      username: getenv.("USER"),
      password: nil,
      hostname: "127.0.0.1",
      port: 5432,
      database: "ash_platform_dev",
      pool_size: 2
    ]
  end

  defp local_or_acceptance_config!(environment, getenv) do
    if present?(getenv.("ASH_PLATFORM_AUTOLAUNCH_LAB_CONFIG")) do
      acceptance_config!(environment, getenv)
    end
  end

  defp acceptance_config!(environment, getenv) do
    run_id = getenv.("ASH_PLATFORM_ACCEPTANCE_RUN_ID")
    username = getenv.("USER")

    unless present?(run_id) and present?(username) do
      raise "Autolaunch lab requires ASH_PLATFORM_ACCEPTANCE_RUN_ID and USER"
    end

    config = [
      hostname: "127.0.0.1",
      port: 5432,
      database: "ash_platform_acceptance_#{run_id}",
      username: username,
      password: nil,
      pool_size: 2
    ]

    environment_values =
      Map.new(
        ~w(DATABASE_URL DATABASE_DIRECT_URL DATABASE_POOLED_URL FLY_APP_NAME FLY_REGION ASH_PLATFORM_ACCEPTANCE_RUN_ID),
        &{&1, getenv.(&1)}
      )

    AshPlatform.LocalDatabaseFixture.reject_remote_environment!(environment_values)
    AshPlatform.LocalDatabaseFixture.validate_acceptance_target!(:test, config, username)

    if environment in [:dev, :test] do
      config
    else
      raise "Autolaunch lab database is development/test only"
    end
  end

  defp valid_userinfo?(userinfo) when is_binary(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [username, password] -> present?(username) and present?(password)
      _ -> false
    end
  end

  defp valid_userinfo?(_userinfo), do: false

  defp production_identity?(%URI{} = uri) do
    [uri.host, uri.path, uri.userinfo]
    |> Enum.any?(&production_identity?/1)
  end

  defp production_identity?(value) when is_binary(value) do
    decoded = decode(value) |> String.downcase()
    Enum.any?(@production_identities, &String.contains?(decoded, &1))
  end

  defp production_identity?(_value), do: false

  defp decode(value) do
    URI.decode(value)
  rescue
    _error -> value
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp remote_target_error do
    "remote database access requires cluster nvwq9ozp9ye03kl1 named regents-pg-test"
  end
end
