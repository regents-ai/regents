defmodule RegentPoints.WalletSnapshot do
  @moduledoc "Append-only wallet evidence captured from every writer of the canonical account table."
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "wallet_snapshots"
    schema "regent_points"
    repo &RegentPoints.repo/2

    custom_indexes do
      index [:account_id, :effective_at, :id]
    end

    custom_statements do
      statement :capture_verified_wallets do
        up """
        CREATE FUNCTION regent_points.verified_wallets(primary_wallet text, other_wallets text[])
        RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
          SELECT COALESCE(array_agg(DISTINCT lower(wallet) ORDER BY lower(wallet)), ARRAY[]::text[])
          FROM unnest(COALESCE(other_wallets, ARRAY[]::text[]) || ARRAY[primary_wallet]) AS wallet
          WHERE wallet IS NOT NULL AND wallet <> '';
        $$;

        CREATE FUNCTION regent_points.capture_verified_wallets() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          IF TG_OP = 'INSERT' OR
             regent_points.verified_wallets(NEW.wallet_address, NEW.wallet_addresses)
             IS DISTINCT FROM regent_points.verified_wallets(OLD.wallet_address, OLD.wallet_addresses) THEN
            INSERT INTO regent_points.wallet_snapshots(account_id, wallet_addresses, effective_at)
            VALUES (NEW.id, regent_points.verified_wallets(NEW.wallet_address, NEW.wallet_addresses),
                    clock_timestamp() AT TIME ZONE 'utc');
          END IF;
          RETURN NEW;
        END;
        $$;

        LOCK TABLE regent_names.platform_human_users IN SHARE ROW EXCLUSIVE MODE;
        INSERT INTO regent_points.wallet_coverage(id, starts_at)
        VALUES (1, clock_timestamp() AT TIME ZONE 'utc');
        INSERT INTO regent_points.wallet_snapshots(account_id, wallet_addresses, effective_at)
        SELECT id, regent_points.verified_wallets(wallet_address, wallet_addresses),
               (SELECT starts_at FROM regent_points.wallet_coverage WHERE id = 1)
        FROM regent_names.platform_human_users;

        CREATE TRIGGER points_verified_wallets
        AFTER INSERT OR UPDATE OF wallet_address, wallet_addresses ON regent_names.platform_human_users
        FOR EACH ROW EXECUTE FUNCTION regent_points.capture_verified_wallets();

        CREATE FUNCTION regent_points.refuse_snapshot_change() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          RAISE EXCEPTION 'regent_points.% rows are final', TG_TABLE_NAME;
        END;
        $$;
        CREATE TRIGGER wallet_snapshots_are_final BEFORE UPDATE OR DELETE ON regent_points.wallet_snapshots
        FOR EACH ROW EXECUTE FUNCTION regent_points.refuse_snapshot_change();
        CREATE TRIGGER wallet_coverage_is_final BEFORE UPDATE OR DELETE ON regent_points.wallet_coverage
        FOR EACH ROW EXECUTE FUNCTION regent_points.refuse_snapshot_change();
        CREATE TRIGGER period_snapshots_are_final BEFORE UPDATE OR DELETE ON regent_points.period_snapshots
        FOR EACH ROW EXECUTE FUNCTION regent_points.refuse_snapshot_change();
        """

        down """
        DROP TRIGGER points_verified_wallets ON regent_names.platform_human_users;
        DROP FUNCTION regent_points.capture_verified_wallets();
        DROP FUNCTION regent_points.verified_wallets(text, text[]);
        DROP TRIGGER wallet_snapshots_are_final ON regent_points.wallet_snapshots;
        DROP TRIGGER wallet_coverage_is_final ON regent_points.wallet_coverage;
        DROP TRIGGER period_snapshots_are_final ON regent_points.period_snapshots;
        DROP FUNCTION regent_points.refuse_snapshot_change();
        """
      end
    end
  end

  attributes do
    integer_primary_key :id
    attribute :account_id, :integer, allow_nil?: false
    attribute :wallet_addresses, {:array, :string}, allow_nil?: false
    attribute :effective_at, :utc_datetime_usec, allow_nil?: false
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  @doc """
  The account whose verified wallets held `wallet`, a lowercase address, at
  `at`. Only the last version of each account at that moment counts, so a
  wallet removed before `at` has no owner then. No version, or more than one
  account holding the wallet, is `:unknown_owner`; it never answers with a
  later or current owner.
  """
  @spec owner(String.t(), DateTime.t()) :: {:ok, integer()} | {:error, :unknown_owner}
  def owner(wallet, %DateTime{} = at) do
    sql = """
    WITH latest AS (
      SELECT DISTINCT ON (account_id) account_id, wallet_addresses
      FROM regent_points.wallet_snapshots WHERE effective_at <= $2
      ORDER BY account_id, effective_at DESC, id DESC
    )
    SELECT account_id FROM latest WHERE $1 = ANY(wallet_addresses)
    """

    case RegentPoints.repo(nil, :read).query!(sql, [wallet, DateTime.to_naive(at)]) do
      %{rows: [[account_id]]} -> {:ok, account_id}
      %{rows: _none_or_many} -> {:error, :unknown_owner}
    end
  end
end
