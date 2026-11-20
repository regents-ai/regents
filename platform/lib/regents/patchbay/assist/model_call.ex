defmodule Regents.Patchbay.Assist.ModelCall do
  @moduledoc """
  One question Patchbay sent a model on OpenRouter: Jev, or the model that
  drafts a tool's arguments. It is written before the question is sent, so
  the limits count questions still in flight as well as answered ones, and
  closed with the tokens and cost the provider said the answer took.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Assist,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Patchbay.Assist.Types.ModelCallOutcome
  alias Regents.Patchbay.Assist.Types.ModelCallPurpose

  postgres do
    table("assist_model_calls")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:assist_run, on_delete: :nilify)
    end

    custom_indexes do
      # The deployment's daily ceiling counts every question of the last day.
      index([:inserted_at])
      # The posting check's limits count its readings, and each person's.
      index([:purpose, :visitor_key, :inserted_at])
      # A run's removal clears its questions' link to it.
      index([:assist_run_id])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:purpose, ModelCallPurpose, allow_nil?: false, public?: true)
    attribute(:model, :string, allow_nil?: false, public?: true)

    # Who a limit counts the question against: the person a post is read for.
    # Questions the earlier free help asked hold the key of the connection
    # that asked.
    attribute(:visitor_key, :string, allow_nil?: true, public?: true)

    attribute(:outcome, ModelCallOutcome, allow_nil?: false, default: :asked, public?: true)

    # What the provider said the answer took, when it said.
    attribute(:prompt_tokens, :integer, allow_nil?: true, public?: true)
    attribute(:completion_tokens, :integer, allow_nil?: true, public?: true)
    attribute(:cost_usd, :decimal, allow_nil?: true, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:assist_run, Regents.Patchbay.Assist.Run, allow_nil?: true, public?: true)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
