defmodule Regents.Autolaunch.ShareVideoRequest do
  @moduledoc """
  One share video asked for and, once made, the video itself: what it is of (a
  launch's token or running auction, by `auction_id`; a covered-call market or
  an Isolated Exposure to After-hours Stocks series, by `subject`, its symbol
  or address), and for a person's own video the signed-in account and its
  wallet. A launch's own video is named by `key`, which moves on every fifteen
  minutes; a person's are theirs for that launch or market, kind and wallet.

  A video is queued once: a request for a video already queued is that queued
  row (the `:queued_key` identity). A video made once saved videos were full
  is not saved (`saved` false).

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "share_video_requests"
    schema("autolaunch_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:key, :inserted_at])
      index([:state, :inserted_at])
      index([:human_account_id, :inserted_at])
      index([:human_account_id, :auction_id, :kind, :inserted_at])
      index([:human_account_id, :subject, :kind, :inserted_at])
    end

    identity_wheres_to_sql(queued_key: "state = 'queued'")
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string, allow_nil?: false

    attribute :kind, :atom,
      allow_nil?: false,
      constraints: [one_of: [:token, :auction, :covered_calls, :exposure]]

    # The launch, for a token's or an auction's video.
    attribute :auction_id, :uuid
    # The market's symbol or the series' address, for a covered-call or an
    # Isolated Exposure to After-hours Stocks video.
    attribute :subject, :string
    # The signed-in account a person's own video is for; nil for a launch's own.
    attribute :human_account_id, :integer
    attribute :wallet, :string

    # The finished MP4.
    attribute :mp4, :binary, select_by_default?: false
    # False for a video made once saved videos were full: it is handed over once.
    attribute :saved, :boolean, allow_nil?: false, default: true

    attribute :state, :atom,
      allow_nil?: false,
      constraints: [one_of: [:queued, :ready, :failed]]

    timestamps()
  end

  identities do
    identity :queued_key, [:key], where: expr(state == :queued)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
