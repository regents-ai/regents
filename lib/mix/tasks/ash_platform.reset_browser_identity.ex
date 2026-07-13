defmodule Mix.Tasks.AshPlatform.ResetBrowserIdentity do
  use Mix.Task

  @moduledoc false
  @shortdoc "Removes only the acceptance-run browser identity proof"

  defmodule Preflight do
    @moduledoc false
    defstruct [:run_id, :repo_config, :environment, :adapter, :identity]
  end

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    run_id = System.fetch_env!("ASH_PLATFORM_ACCEPTANCE_RUN_ID")
    proof = preflight!(run_id)
    reset!(preflight: proof)
  end

  def reset!(opts \\ []) do
    proof =
      case Keyword.fetch(opts, :preflight) do
        {:ok, %Preflight{} = proof} ->
          proof

        :error ->
          environment = Keyword.get(opts, :environment, System.get_env())
          preflight!(environment["ASH_PLATFORM_ACCEPTANCE_RUN_ID"], opts)

        _ ->
          raise "browser identity reset requires its guarded preflight"
      end

    adapter = proof.adapter
    identity = proof.identity

    adapter.transaction(fn ->
      case adapter.identity_rows(identity.privy_user_id) do
        [] ->
          %{regents: 0, identities: 0}

        [[account_id, wallet_address, wallet_addresses]] ->
          verify_identity!(identity, wallet_address, wallet_addresses)
          regents = adapter.delete_regents(account_id)
          identities = adapter.delete_identity(account_id, identity.privy_user_id)

          unless identities == 1 do
            raise "browser identity reset could not remove the run-owned identity"
          end

          %{regents: regents, identities: identities}

        _rows ->
          raise "browser identity reset found ambiguous run-owned identity"
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def preflight!(run_id, opts \\ []) do
    env = Keyword.get(opts, :env, current_env())
    repo_config = Keyword.get(opts, :repo_config, AshPlatform.Repo.config())
    environment = Keyword.get(opts, :environment, System.get_env())
    adapter = Keyword.get(opts, :adapter, __MODULE__.RepoAdapter)

    validate_target!(env, repo_config, environment, run_id)
    identity = owned_identity!(opts, env, adapter)
    marker_rows = adapter.ownership_marker_rows()

    AshPlatform.LocalDatabaseFixture.validate_ownership_marker!(
      marker_rows,
      run_id,
      to_string(repo_config[:database]),
      to_string(repo_config[:username])
    )

    %Preflight{
      run_id: run_id,
      repo_config: repo_config,
      environment: environment,
      adapter: adapter,
      identity: identity
    }
  end

  defp validate_target!(env, repo_config, environment, run_id)
       when is_binary(run_id) and run_id != "" do
    unless environment["ASH_PLATFORM_ACCEPTANCE_RUN_ID"] == run_id do
      raise "browser identity reset refused mismatched acceptance run"
    end

    AshPlatform.LocalDatabaseFixture.reject_remote_environment!(environment)
    expected_username = System.fetch_env!("USER")

    AshPlatform.LocalDatabaseFixture.validate_acceptance_target!(
      env,
      repo_config,
      expected_username
    )

    unless to_string(repo_config[:database]) == "ash_platform_acceptance_" <> run_id do
      raise "browser identity reset refused mismatched acceptance run"
    end

    :ok
  end

  defp validate_target!(_env, _repo_config, _environment, _run_id) do
    raise "browser identity reset requires an acceptance run"
  end

  defp owned_identity!(opts, env, adapter) do
    case Keyword.fetch(opts, :owned_identity) do
      {:ok, identity}
      when env == :test and adapter != __MODULE__.RepoAdapter and is_map(identity) ->
        identity

      :error ->
        configured_identity!()

      _ ->
        raise "browser identity reset refused injected identity evidence"
    end
  end

  defp configured_identity! do
    verifier = Application.fetch_env!(:ash_platform, :privy_verifier)

    case verifier.verify_access_token("valid") do
      {:ok, %{privy_user_id: did, wallet_address: wallet, wallet_addresses: wallets}}
      when is_binary(did) and is_binary(wallet) and is_list(wallets) ->
        %{privy_user_id: did, wallet_address: wallet, wallet_addresses: wallets}

      _ ->
        raise "browser identity reset could not resolve the local verifier identity"
    end
  end

  defp verify_identity!(identity, wallet_address, wallet_addresses) do
    if wallet_address == identity.wallet_address and wallet_addresses == identity.wallet_addresses do
      :ok
    else
      raise "browser identity reset found mismatched run-owned identity evidence"
    end
  end

  defp current_env do
    if Code.ensure_loaded?(Mix), do: Mix.env(), else: :prod
  end

  defmodule RepoAdapter do
    @moduledoc false

    def transaction(fun), do: AshPlatform.Repo.transaction(fun)

    def ownership_marker_rows do
      query!(
        "SELECT run_id, database_name, database_owner FROM acceptance_harness.baseline",
        []
      ).rows
    end

    def identity_rows(privy_user_id) do
      query!(
        "SELECT id, wallet_address, wallet_addresses FROM platform.platform_human_users WHERE privy_user_id = $1 FOR UPDATE",
        [privy_user_id]
      ).rows
    end

    def delete_regents(account_id) do
      query!("DELETE FROM public.regents WHERE human_account_id = $1", [account_id]).num_rows
    end

    def delete_identity(account_id, privy_user_id) do
      query!(
        "DELETE FROM platform.platform_human_users WHERE id = $1 AND privy_user_id = $2",
        [account_id, privy_user_id]
      ).num_rows
    end

    defp query!(sql, params), do: Ecto.Adapters.SQL.query!(AshPlatform.Repo, sql, params)
  end
end
