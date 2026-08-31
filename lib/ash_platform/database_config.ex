defmodule AshPlatform.DatabaseConfig do
  @moduledoc false

  @cluster_id "nvwq9ozp9ye03kl1"
  @cluster_name "regents-pg-test"
  @production_database_host "direct.nvwq9ozp9ye03kl1.flympg.net"
  @production_identities ["regents-platform-prod", "platform-phx"]
  @rehearsal_target_error "database migration requires rehearsal mode for cluster nvwq9ozp9ye03kl1 named regents-pg-test"
  @production_migration_error "production migration requires separate Chief-authorized production migration configuration"

  def runtime_config!(environment, getenv \\ &System.get_env/1)

  def runtime_config!(:test, _getenv), do: nil

  def runtime_config!(:prod, getenv) do
    database_url!(getenv, "DATABASE_POOLED_URL", @production_database_host)
  end

  def runtime_config!(:dev, getenv) do
    case remote_target(getenv) do
      :local -> local_config(getenv)
      :remote -> database_url!(getenv, "DATABASE_POOLED_URL")
    end
  end

  def runtime_config!(_environment, _getenv), do: nil

  def release_config!(getenv \\ &System.get_env/1) do
    require_rehearsal_target!(getenv)
    database_url!(getenv, "DATABASE_DIRECT_URL", @production_database_host)
  end

  defp database_url!(getenv, variable, required_host \\ nil) do
    with value when is_binary(value) and value != "" <- getenv.(variable),
         {:ok, %URI{scheme: scheme, host: host, path: "/" <> database, userinfo: userinfo} = uri} <-
           parse_uri(value),
         true <- scheme in ["postgres", "postgresql"],
         true <- present?(host),
         true <- present?(database),
         true <- valid_userinfo?(userinfo),
         false <- production_identity?(uri),
         {:ok, admitted_host} <- admit_host(host, required_host),
         true <- safe_query?(uri),
         true <- safe_port?(uri),
         true <- valid_ecto_url?(value) do
      connection_options(canonical_url(value, uri, required_host), admitted_host)
    else
      nil -> raise "#{variable} is required"
      "" -> raise "#{variable} is required"
      _ -> raise "#{variable} must be a valid PostgreSQL URL for the approved target"
    end
  end

  defp admit_host(host, nil), do: {:ok, host}

  defp admit_host(host, required_host) do
    if String.downcase(host) == required_host,
      do: {:ok, required_host},
      else: :error
  end

  defp canonical_url(value, _uri, nil), do: value
  defp canonical_url(_value, uri, required_host), do: URI.to_string(%{uri | host: required_host})

  defp parse_uri(value) do
    URI.new(value)
  rescue
    _error -> :error
  end

  defp valid_ecto_url?(value) do
    Ecto.Repo.Supervisor.parse_url(value)
    true
  rescue
    _error -> false
  end

  # Ecto turns every URL query key into an atom and merges parsed URL options
  # after the explicit Repo configuration. MPG URLs therefore admit no query
  # options: even encoded or future aliases cannot weaken TLS, replace the
  # endpoint, or restore named prepares after this module's checks.
  defp safe_query?(%URI{host: host, query: query}) do
    not fly_mpg_host?(host) or query in [nil, ""]
  end

  defp safe_port?(%URI{host: host, port: port}) do
    not fly_mpg_host?(host) or port in [nil, 5432]
  end

  defp connection_options(value, host) do
    options = [url: value, socket_options: [:inet6]]

    if fly_mpg_host?(host) do
      options =
        options
        |> Keyword.put(:port, 5432)
        |> Keyword.put(:ssl,
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(host),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        )

      if fly_mpg_pgbouncer_host?(host),
        do: Keyword.put(options, :prepare, :unnamed),
        else: options
    else
      options
    end
  end

  defp fly_mpg_host?(host) when is_binary(host) do
    host = String.downcase(host)
    host != "flympg.net" and String.ends_with?(host, ".flympg.net")
  end

  defp fly_mpg_host?(_host), do: false

  defp fly_mpg_pgbouncer_host?(host) do
    host |> String.downcase() |> String.starts_with?("pgbouncer.")
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
