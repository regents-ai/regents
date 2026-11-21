defmodule Regents.Autolaunch.CoveredCalls.Cursor do
  @moduledoc """
  How far the site has read one market's covered-calls contract, at the latest
  block: the first block not read yet, and the head and when it was last seen.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch.CoveredCalls,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @address ~r/\A0x[0-9a-f]{40}\z/
  @hash ~r/\A0x[0-9a-f]{64}\z/

  postgres do
    table "covered_call_cursors"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id
    attribute :chain_id, :integer, allow_nil?: false, constraints: [min: 1]
    attribute :contract, :string, allow_nil?: false, constraints: [match: @address]
    # The first block not read yet.
    attribute :next_block, :integer, allow_nil?: false, constraints: [min: 0]
    attribute :head_block, :integer, constraints: [min: 0]
    attribute :head_block_hash, :string, constraints: [match: @hash]
    # When the head was last read.
    attribute :observed_at, :utc_datetime_usec
  end

  identities do
    identity :contract, [:chain_id, :contract]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
