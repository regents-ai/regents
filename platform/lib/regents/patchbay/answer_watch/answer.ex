defmodule Regents.Patchbay.AnswerWatch.Answer do
  @moduledoc """
  One engine's answer to one tracked question in one week: the answer's
  words, the addresses it cites, and whether it links Patchbay (cites an
  address on patchbay.help) or names it. The question's persona, stage and
  topic are copied in when the answer is written, so later edits to the
  question list never change what an earlier week recorded.

  The table and its rows as patchbay.help keeps them; no page here reads them.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.AnswerWatch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("answer_watch_answers")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    # The Monday (UTC) of the week the answer was asked in.
    attribute(:week, :date, allow_nil?: false, public?: true)

    attribute(:engine, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:chatgpt, :perplexity]]
    )

    attribute(:question, :string, allow_nil?: false, public?: true)

    attribute(:persona, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [
        one_of: [:agent_builders, :site_teams, :wallet_teams, :agents, :security, :marketers]
      ]
    )

    attribute(:stage, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:stuck, :looking, :comparing, :choosing]]
    )

    attribute(:topic, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:agent_help, :webmcp, :wallets, :incidents, :offers, :patchbay]]
    )

    # The model that answered, as the provider named it.
    attribute(:model, :string, allow_nil?: false, public?: true)
    attribute(:answer, :string, allow_nil?: false, public?: true, constraints: [trim?: false])
    attribute(:cited_urls, {:array, :string}, allow_nil?: false, default: [], public?: true)
    attribute(:patchbay_cited, :boolean, allow_nil?: false, public?: true)
    attribute(:patchbay_mentioned, :boolean, allow_nil?: false, public?: true)

    create_timestamp(:inserted_at)
  end

  identities do
    identity(:once_a_week, [:week, :engine, :question])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
