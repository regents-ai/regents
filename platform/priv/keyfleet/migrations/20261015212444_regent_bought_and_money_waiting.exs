defmodule Regents.Repo.Migrations.KeyfleetRegentBoughtAndMoneyWaiting do
  @moduledoc """
  REGENT bought for a fleet in its money history, and since when its
  protocol share and its USDC waiting to turn into REGENT have waited.

  Generated with `mix ash.codegen`. The waiting amount defaults to nothing in
  the database, so a machine still running the previous release keeps saving
  readings while the release rolls out.
  """

  use Ecto.Migration

  def up do
    alter table(:treasury_readings) do
      add(:conversion_waiting, :decimal, null: false, default: 0)
      add(:protocol_share_owed_since, :utc_datetime_usec)
      add(:conversion_waiting_since, :utc_datetime_usec)
    end

    create constraint(:treasury_readings, :treasury_readings_nonnegative_conversion_waiting,
             check: """
               conversion_waiting >= 0
             """
           )

    alter table(:treasury_events) do
      add(:usdc_in, :decimal)
      add(:weth_mid, :decimal)
      add(:regent_out, :decimal)
    end

    drop_if_exists(constraint(:treasury_events, :treasury_events_shape))

    create constraint(:treasury_events, :treasury_events_shape,
             check: """
               (kind = 'advance_returned' AND num_nonnulls(advance_id, by, amount, outstanding) = 4 AND num_nulls(asset, account, share, balance, per_key, keys, bps, voted, purpose_hash, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 16)
             OR (kind = 'advanced' AND num_nonnulls(advance_id, account, asset, share, amount, purpose_hash) = 6 AND num_nulls(by, balance, per_key, keys, bps, voted, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 14)
             OR (kind = 'claimed' AND num_nonnulls(asset, account, by, amount) = 4 AND num_nulls(share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 16)
             OR (kind = 'daily_split_rate_set' AND num_nonnulls(bps) = 1 AND num_nulls(asset, account, by, share, amount, balance, per_key, keys, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 19)
             OR (kind = 'daily_split_run' AND num_nonnulls(voted, keys, bps) = 3 AND num_nulls(asset, account, by, share, amount, balance, per_key, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 17)
             OR (kind = 'forwarded' AND num_nonnulls(asset, by, amount) = 3 AND num_nulls(account, share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 17)
             OR (kind = 'launch_token_bound' AND num_nonnulls(launch_id, asset, threshold) = 3 AND num_nulls(account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 17)
             OR (kind = 'ousd_admitted' AND num_nonnulls(asset, threshold) = 2 AND num_nulls(account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 18)
             OR (kind = 'paid' AND num_nonnulls(asset, account, share, amount) = 4 AND num_nulls(by, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 16)
             OR (kind = 'protocol_share_sent' AND num_nonnulls(by, amount) = 2 AND num_nulls(asset, account, share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 18)
             OR (kind = 'regent_bought' AND num_nonnulls(usdc_in, weth_mid, regent_out) = 3 AND num_nulls(asset, account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 17)
             OR (kind = 'settled' AND num_nonnulls(token_id, asset, account, amount) = 4 AND num_nulls(by, share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, signed_hash, usdc_in, weth_mid, regent_out) = 16)
             OR (kind = 'signature_approved' AND num_nonnulls(signed_hash) = 1 AND num_nulls(asset, account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, usdc_in, weth_mid, regent_out) = 19)
             OR (kind = 'signature_revoked' AND num_nonnulls(signed_hash) = 1 AND num_nulls(asset, account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, usdc_in, weth_mid, regent_out) = 19)
             OR (kind = 'split_allocated' AND num_nonnulls(asset, balance, per_key, keys) = 4 AND num_nulls(account, by, share, amount, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 16)
             OR (kind = 'split_skipped' AND num_nonnulls(asset, balance) = 2 AND num_nulls(account, by, share, amount, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 18)
             OR (kind = 'split_transfer_failed' AND num_nonnulls(asset, amount) = 2 AND num_nulls(account, by, share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash, usdc_in, weth_mid, regent_out) = 18)
             """
           )

    create constraint(:treasury_events, :treasury_events_nonnegative_usdc_in,
             check: """
               usdc_in >= 0
             """
           )

    create constraint(:treasury_events, :treasury_events_nonnegative_weth_mid,
             check: """
               weth_mid >= 0
             """
           )

    create constraint(:treasury_events, :treasury_events_nonnegative_regent_out,
             check: """
               regent_out >= 0
             """
           )
  end

  def down do
    drop_if_exists(constraint(:treasury_events, :treasury_events_nonnegative_regent_out))

    drop_if_exists(constraint(:treasury_events, :treasury_events_nonnegative_weth_mid))

    drop_if_exists(constraint(:treasury_events, :treasury_events_nonnegative_usdc_in))

    drop_if_exists(constraint(:treasury_events, :treasury_events_shape))

    create constraint(:treasury_events, :treasury_events_shape,
             check: """
               (kind = 'advance_returned' AND num_nonnulls(advance_id, by, amount, outstanding) = 4 AND num_nulls(asset, account, share, balance, per_key, keys, bps, voted, purpose_hash, threshold, launch_id, token_id, signed_hash) = 13)
             OR (kind = 'advanced' AND num_nonnulls(advance_id, account, asset, share, amount, purpose_hash) = 6 AND num_nulls(by, balance, per_key, keys, bps, voted, outstanding, threshold, launch_id, token_id, signed_hash) = 11)
             OR (kind = 'claimed' AND num_nonnulls(asset, account, by, amount) = 4 AND num_nulls(share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 13)
             OR (kind = 'daily_split_rate_set' AND num_nonnulls(bps) = 1 AND num_nulls(asset, account, by, share, amount, balance, per_key, keys, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 16)
             OR (kind = 'daily_split_run' AND num_nonnulls(voted, keys, bps) = 3 AND num_nulls(asset, account, by, share, amount, balance, per_key, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 14)
             OR (kind = 'forwarded' AND num_nonnulls(asset, by, amount) = 3 AND num_nulls(account, share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 14)
             OR (kind = 'launch_token_bound' AND num_nonnulls(launch_id, asset, threshold) = 3 AND num_nulls(account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, token_id, signed_hash) = 14)
             OR (kind = 'ousd_admitted' AND num_nonnulls(asset, threshold) = 2 AND num_nulls(account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, launch_id, token_id, signed_hash) = 15)
             OR (kind = 'paid' AND num_nonnulls(asset, account, share, amount) = 4 AND num_nulls(by, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 13)
             OR (kind = 'protocol_share_sent' AND num_nonnulls(by, amount) = 2 AND num_nulls(asset, account, share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 15)
             OR (kind = 'settled' AND num_nonnulls(token_id, asset, account, amount) = 4 AND num_nulls(by, share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, signed_hash) = 13)
             OR (kind = 'signature_approved' AND num_nonnulls(signed_hash) = 1 AND num_nulls(asset, account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id) = 16)
             OR (kind = 'signature_revoked' AND num_nonnulls(signed_hash) = 1 AND num_nulls(asset, account, by, share, amount, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id) = 16)
             OR (kind = 'split_allocated' AND num_nonnulls(asset, balance, per_key, keys) = 4 AND num_nulls(account, by, share, amount, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 13)
             OR (kind = 'split_skipped' AND num_nonnulls(asset, balance) = 2 AND num_nulls(account, by, share, amount, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 15)
             OR (kind = 'split_transfer_failed' AND num_nonnulls(asset, amount) = 2 AND num_nulls(account, by, share, balance, per_key, keys, bps, voted, advance_id, purpose_hash, outstanding, threshold, launch_id, token_id, signed_hash) = 15)
             """
           )

    alter table(:treasury_events) do
      remove(:regent_out)
      remove(:weth_mid)
      remove(:usdc_in)
    end

    drop_if_exists(
      constraint(:treasury_readings, :treasury_readings_nonnegative_conversion_waiting)
    )

    alter table(:treasury_readings) do
      remove(:conversion_waiting_since)
      remove(:protocol_share_owed_since)
      remove(:conversion_waiting)
    end
  end
end
