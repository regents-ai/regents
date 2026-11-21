defmodule Regents.Repo.Migrations.KeyfleetAddLeftMessages do
  @moduledoc """
  The messages people and agents leave for the site's team
  (`Keyfleet.LeftMessages.LeftMessage`): each names its sender, a person, an
  agent's profile or both. A new, empty table; nothing that exists changes.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create table(:left_messages, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:topic, :text, null: false)
      add(:body, :text, null: false)
      add(:reply_to, :text)
      add(:sender_name, :text, null: false)
      add(:operation_id, :uuid)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :human_account_id,
        references(:platform_human_users,
          column: :id,
          name: "left_messages_human_account_id_fkey",
          type: :bigint,
          prefix: "regent_names",
          on_delete: :restrict
        )
      )

      add(
        :agent_profile_id,
        references(:agent_profiles,
          column: :id,
          name: "left_messages_agent_profile_id_fkey",
          type: :uuid,
          prefix: "keyfleet_app",
          on_delete: :restrict
        )
      )
    end

    create unique_index(:left_messages, [:agent_profile_id, :operation_id],
             name: "left_messages_one_per_operation_index"
           )

    create constraint(:left_messages, :has_sender,
             check: """
               human_account_id IS NOT NULL OR agent_profile_id IS NOT NULL
             """
           )

    create index(:left_messages, [:inserted_at, :id])
  end

  def down do
    drop_if_exists(index(:left_messages, [:inserted_at, :id]))

    drop_if_exists(constraint(:left_messages, :has_sender))

    drop(constraint(:left_messages, "left_messages_agent_profile_id_fkey"))

    drop(constraint(:left_messages, "left_messages_human_account_id_fkey"))

    drop_if_exists(
      unique_index(:left_messages, [:agent_profile_id, :operation_id],
        name: "left_messages_one_per_operation_index"
      )
    )

    drop(table(:left_messages))
  end
end
