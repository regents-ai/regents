defmodule Mix.Tasks.AshPlatform.SeedBrowserAutolaunchDraftOwner do
  use Mix.Task

  @shortdoc "Seeds the local account and Regent needed by the private draft browser proof"

  @fixture_token "valid-autolaunch-draft"
  @regent_slug "draft-browser-regent"
  @regent_display_name "Draft Browser Regent"

  @impl true
  def run(_args) do
    env = Mix.env()
    repo_config = AshPlatform.Repo.config()
    validate_target!(env, repo_config)

    Mix.Task.run("app.start")
    seed!()
  end

  def seed!(opts \\ []) do
    adapter = Keyword.get(opts, :adapter, __MODULE__.RepoAdapter)
    %{privy_user_id: privy_user_id, wallet_address: wallet_address} = fixture_identity!()

    case apply(adapter, :transaction, [
           fn ->
             account_id = ensure_account!(adapter, privy_user_id, wallet_address)
             ensure_regent!(adapter, account_id)
           end
         ]) do
      {:ok, :ok} -> :ok
      {:error, error} -> raise error
    end
  end

  def validate_target!(env, repo_config) when is_list(repo_config) do
    AshPlatform.LocalDatabaseFixture.validate_target!(env, repo_config)
    database = to_string(repo_config[:database])

    if env == :test and String.ends_with?(database, "_test") do
      :ok
    else
      raise "browser Autolaunch draft owner seed refused unsafe database target"
    end
  end

  defp fixture_identity! do
    case AshPlatform.TestPrivyVerifier.verify_access_token(@fixture_token) do
      {:ok,
       %AshPlatform.VerifiedPrivyIdentity{
         privy_user_id: privy_user_id,
         wallet_address: wallet_address,
         wallet_addresses: [wallet_address]
       }}
      when is_binary(privy_user_id) and is_binary(wallet_address) ->
        %{privy_user_id: privy_user_id, wallet_address: wallet_address}

      other ->
        raise "browser Autolaunch draft owner seed fixture identity mismatch: #{inspect(other)}"
    end
  end

  defp ensure_account!(adapter, privy_user_id, wallet_address) do
    rows = apply(adapter, :find_accounts_by_privy_id, [privy_user_id])

    case rows do
      [] ->
        apply(adapter, :insert_account, [privy_user_id, wallet_address])
        |> case do
          [[account_id]] -> account_id
          _ -> raise "browser Autolaunch draft owner seed account insert was ambiguous"
        end

      [[account_id, ^privy_user_id, ^wallet_address, wallet_addresses]]
      when wallet_addresses == [wallet_address] ->
        account_id

      [_row] ->
        raise "browser Autolaunch draft owner seed account or wallet evidence conflicts"

      _rows ->
        raise "browser Autolaunch draft owner seed account or wallet evidence is ambiguous"
    end
  end

  defp ensure_regent!(adapter, account_id) do
    rows = apply(adapter, :find_regents, [account_id, @regent_slug])

    account_regents = Enum.filter(rows, &(&1 |> Enum.at(3) == account_id))
    slug_regents = Enum.filter(rows, &(&1 |> Enum.at(1) == @regent_slug))

    case {account_regents, slug_regents} do
      {[], []} ->
        apply(adapter, :insert_regent, [@regent_slug, @regent_display_name, account_id])

        :ok

      {[account_regent], [slug_regent]} ->
        if account_regent == slug_regent and exact_regent?(account_regent, account_id) do
          :ok
        else
          raise "browser Autolaunch draft owner seed Regent identity conflicts"
        end

      {[_], []} ->
        raise "browser Autolaunch draft owner seed Regent identity conflicts"

      {[], [_]} ->
        raise "browser Autolaunch draft owner seed Regent identity conflicts"

      _ ->
        raise "browser Autolaunch draft owner seed Regent identity is ambiguous"
    end
  end

  defp exact_regent?([_id, slug, display_name, human_account_id], account_id) do
    slug == @regent_slug and display_name == @regent_display_name and
      human_account_id == account_id
  end

  defmodule RepoAdapter do
    @moduledoc false

    def transaction(fun), do: AshPlatform.Repo.transaction(fun)

    def find_accounts_by_privy_id(privy_user_id) do
      query!(
        """
        SELECT id, privy_user_id, wallet_address, wallet_addresses
        FROM platform.platform_human_users
        WHERE privy_user_id = $1
        FOR UPDATE
        """,
        [privy_user_id]
      ).rows
    end

    def insert_account(privy_user_id, wallet_address) do
      query!(
        """
        INSERT INTO platform.platform_human_users
          (privy_user_id, wallet_address, wallet_addresses, created_at, updated_at)
        VALUES ($1, $2, ARRAY[$2]::varchar[], now(), now())
        RETURNING id
        """,
        [privy_user_id, wallet_address]
      ).rows
    end

    def find_regents(account_id, slug) do
      query!(
        """
        SELECT id, slug, display_name, human_account_id
        FROM regents
        WHERE human_account_id = $1 OR slug = $2
        FOR UPDATE
        """,
        [account_id, slug]
      ).rows
    end

    def insert_regent(slug, display_name, account_id) do
      query!(
        """
        INSERT INTO regents (slug, display_name, human_account_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, now(), now())
        RETURNING id
        """,
        [slug, display_name, account_id]
      )
    end

    defp query!(sql, params), do: Ecto.Adapters.SQL.query!(AshPlatform.Repo, sql, params)
  end
end
