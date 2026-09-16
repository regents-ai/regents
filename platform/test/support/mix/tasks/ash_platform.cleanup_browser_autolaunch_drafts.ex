defmodule Mix.Tasks.AshPlatform.CleanupBrowserAutolaunchDrafts do
  use Mix.Task

  @shortdoc "Removes one exact private draft created by a local browser proof"
  @draft_name ~r/\A(?:Browser launch draft|Narrow viewport draft) [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  @impl true
  def run(["--name", name]) do
    unless Regex.match?(@draft_name, name), do: Mix.raise("refused non-fixture draft name")
    validate_target!(Mix.env(), AshPlatform.Repo.config())
    Mix.Task.run("app.start")
    validate_target!(Mix.env(), AshPlatform.Repo.config())

    {privy_user_id, wallet_address} = fixture_identity!()

    case AshPlatform.Repo.transaction(fn ->
           %{num_rows: count} =
             Ecto.Adapters.SQL.query!(
               AshPlatform.Repo,
               """
               DELETE FROM autolaunch_app.launch_drafts AS draft
               USING regent_names.platform_human_users AS account
               WHERE draft.token_name = $1
                 AND draft.human_account_id = account.id
                 AND account.privy_user_id = $2
                 AND account.wallet_address = $3
                 AND account.wallet_addresses = ARRAY[$3]::varchar[]
               """,
               [name, privy_user_id, wallet_address],
               log: false
             )

           if count > 1, do: AshPlatform.Repo.rollback(:ambiguous_fixture_name)
           count
         end) do
      {:ok, count} -> Mix.shell().info("Browser drafts removed: #{count}")
      {:error, :ambiguous_fixture_name} -> Mix.raise("refused ambiguous fixture draft name")
    end
  end

  def run(_args),
    do: Mix.raise("usage: ash_platform.cleanup_browser_autolaunch_drafts --name NAME")

  def validate_target!(env, repo_config) do
    Mix.Tasks.AshPlatform.SeedBrowserAutolaunchDraftOwner.validate_target!(env, repo_config)

    unless env == :test and is_nil(repo_config[:url]) and
             repo_config[:hostname] == "127.0.0.1" and
             Keyword.get(repo_config, :port, 5432) == 5432 and
             String.starts_with?(to_string(repo_config[:database]), "ash_platform_") do
      Mix.raise("browser draft cleanup refused unsafe database target")
    end

    :ok
  end

  defp fixture_identity! do
    case AshPlatform.TestPrivyVerifier.verify_access_token("valid-autolaunch-draft") do
      {:ok,
       %AshPlatform.VerifiedPrivyIdentity{
         privy_user_id: privy_user_id,
         wallet_address: wallet_address,
         wallet_addresses: [wallet_address]
       }}
      when is_binary(privy_user_id) and is_binary(wallet_address) ->
        {privy_user_id, wallet_address}

      _ ->
        Mix.raise("browser draft cleanup fixture identity mismatch")
    end
  end
end
