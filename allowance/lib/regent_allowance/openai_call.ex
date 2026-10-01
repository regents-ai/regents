defmodule RegentAllowance.OpenAICall do
  @moduledoc """
  One OpenAI call made for a person: which site made it, the model, the tokens
  it used and what it cost. Rows are only ever added; they are the history of
  money spent.
  """

  use Ash.Resource,
    otp_app: :regent_allowance,
    domain: RegentAllowance,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo &RegentAllowance.repo/2
    schema "regent_allowance"
    table "openai_calls"
    migrate? false
  end

  attributes do
    uuid_primary_key :id

    attribute :privy_user_id, :string, allow_nil?: false, public?: true
    attribute :site, :string, allow_nil?: false, public?: true
    attribute :model, :string, allow_nil?: false, public?: true

    attribute :input_tokens, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    attribute :cached_input_tokens, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    attribute :output_tokens, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    # US dollars, as regent_openai priced the call.
    attribute :cost_usd, :decimal, allow_nil?: false, public?: true, constraints: [min: 0]

    create_timestamp :inserted_at
  end

  actions do
    read :since do
      description "One person's calls from a moment on, on every site."
      argument :privy_user_id, :string, allow_nil?: false
      argument :since, :utc_datetime_usec, allow_nil?: false
      filter expr(privy_user_id == ^arg(:privy_user_id) and inserted_at >= ^arg(:since))
    end

    create :record do
      description "Writes down what one call made for a person cost."

      accept [
        :privy_user_id,
        :site,
        :model,
        :input_tokens,
        :cached_input_tokens,
        :output_tokens,
        :cost_usd
      ]
    end
  end
end
