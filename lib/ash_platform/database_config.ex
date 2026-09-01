defmodule AshPlatform.DatabaseConfig do
  @moduledoc false

  @cluster_id "nvwq9ozp9ye03kl1"
  @cluster_name "regents-pg-test"
  @production_database_host "direct.nvwq9ozp9ye03kl1.flympg.net"
  @production_identities ["regents-platform-prod", "platform-phx"]
  @production_hosts [@production_database_host]
  @staging_hosts ["regents-staging-db.flycast", "regents-staging-db.internal"]
  # The staging role can never reach production, so its refusals name production's
  # cluster, database host, and web application wherever they could appear in a
  # URL -- host, database, or credentials -- not only as the hostname the
  # allowlist already rejects. These terms are staging's alone: production runs as
  # the Fly application regents-sh-web, so refusing that name on the production
  # role would refuse production's own release commands.
  @staging_refusals [
    @cluster_id,
    @production_database_host,
    "regents-sh-web" | @production_identities
  ]
  @deployment_role_variable "ASH_PLATFORM_DEPLOYMENT_ROLE"
  @deployment_role_error ~s(ASH_PLATFORM_DEPLOYMENT_ROLE must be set to "production" or "staging")
  @rehearsal_target_error "database migration requires rehearsal mode for cluster nvwq9ozp9ye03kl1 named regents-pg-test"
  @production_migration_error "production migration requires separate Chief-authorized production migration configuration"

  def runtime_config!(environment, getenv \\ &System.get_env/1)

  def runtime_config!(:test, _getenv), do: nil

  def runtime_config!(:prod, getenv) do
    case deployment_role!(getenv) do
      :production ->
        database_url!(getenv, "DATABASE_POOLED_URL", @production_hosts, @production_identities)

      :staging ->
        database_url!(getenv, "DATABASE_POOLED_URL", @staging_hosts, @staging_refusals)
    end
  end

  def runtime_config!(:dev, getenv) do
    case remote_target(getenv) do
      :local -> local_config(getenv)
      :remote -> database_url!(getenv, "DATABASE_POOLED_URL")
    end
  end

  def runtime_config!(_environment, _getenv), do: nil

  def release_config!(getenv \\ &System.get_env/1) do
    case deployment_role!(getenv) do
      :production ->
        require_rehearsal_target!(getenv)
        database_url!(getenv, "DATABASE_DIRECT_URL", @production_hosts, @production_identities)

      :staging ->
        database_url!(getenv, "DATABASE_DIRECT_URL", @staging_hosts, @staging_refusals)
    end
  end

  # Deployments say which venue they are. There is no default and no fallback
  # between roles: an unset or unrecognized role stops the boot before any
  # database URL is read.
  defp deployment_role!(getenv) do
    case getenv.(@deployment_role_variable) do
      "production" -> :production
      "staging" -> :staging
      _unset_or_unknown -> raise @deployment_role_error
    end
  end

  defp database_url!(
         getenv,
         variable,
         admitted_hosts \\ nil,
         refused_terms \\ @production_identities
       ) do
    with value when is_binary(value) and value != "" <- getenv.(variable),
         {:ok, %URI{scheme: scheme, host: host, path: "/" <> database, userinfo: userinfo} = uri} <-
           parse_uri(value),
         true <- scheme in ["postgres", "postgresql"],
         true <- present?(host),
         true <- present?(database),
         true <- valid_userinfo?(userinfo),
         false <- refused_identity?(uri, refused_terms),
         {:ok, admitted_host} <- admit_host(host, admitted_hosts),
         true <- safe_query?(uri),
         true <- safe_port?(uri),
         true <- valid_ecto_url?(value) do
      connection_options(canonical_url(value, uri, admitted_hosts, admitted_host), admitted_host)
    else
      nil -> raise "#{variable} is required"
      "" -> raise "#{variable} is required"
      _ -> raise "#{variable} must be a valid PostgreSQL URL for the approved target"
    end
  end

  defp admit_host(host, nil), do: {:ok, host}

  defp admit_host(host, admitted_hosts) do
    admitted_host = String.downcase(host)

    if admitted_host in admitted_hosts,
      do: {:ok, admitted_host},
      else: :error
  end

  defp canonical_url(value, _uri, nil, _admitted_host), do: value

  defp canonical_url(_value, uri, _admitted_hosts, admitted_host),
    do: URI.to_string(%{uri | host: admitted_host})

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

  defp refused_identity?(%URI{} = uri, refused_terms) do
    [uri.host, uri.path, uri.userinfo]
    |> Enum.any?(&names_any?(&1, refused_terms))
  end

  defp production_identity?(value), do: names_any?(value, @production_identities)

  defp names_any?(value, terms) when is_binary(value) do
    decoded = decode(value) |> String.downcase()
    Enum.any?(terms, &String.contains?(decoded, &1))
  end

  defp names_any?(_value, _terms), do: false

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
