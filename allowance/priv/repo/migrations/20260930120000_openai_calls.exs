defmodule RegentAllowance.Migrations.OpenAICalls do
  use Ecto.Migration

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS regent_allowance")

    create table(:openai_calls, prefix: "regent_allowance", primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:privy_user_id, :text, null: false)
      add(:site, :text, null: false)
      add(:model, :text, null: false)
      add(:input_tokens, :bigint, null: false)
      add(:cached_input_tokens, :bigint, null: false)
      add(:output_tokens, :bigint, null: false)
      add(:cost_usd, :numeric, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create index(:openai_calls, [:privy_user_id, :inserted_at],
             prefix: "regent_allowance",
             name: :openai_calls_person_day_index
           )
  end

  def down do
    raise "OpenAI spend records are retained history of money spent; restore a reviewed recovery copy instead."
  end
end
