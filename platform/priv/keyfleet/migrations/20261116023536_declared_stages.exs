defmodule Regents.Repo.Migrations.KeyfleetDeclaredStages do
  @moduledoc """
  Rules the database keeps on four records' stages: a Key's small picture is
  never both made and failed, a kept notebook page never succeeded with a
  failure recorded, a project that no Key holds is never archived, and an ENS
  lookup is pending, done or failed. It only adds the rules and changes no row
  or column; a stored row that breaks one stops it.
  """

  use Ecto.Migration

  def up do
    create constraint(:key_pictures, :key_pictures_close_up_made_or_failed,
             check: """
               close_up_cid IS NULL OR close_up_failed_at IS NULL
             """
           )

    create constraint(:key_pictures, :key_pictures_small_card_made_or_failed,
             check: """
               small_card_cid IS NULL OR small_card_failed_at IS NULL
             """
           )

    create constraint(:notebook_saved_outputs, :notebook_saved_outputs_succeeded_or_failed,
             check: """
               NOT succeeded OR failure IS NULL
             """
           )

    create constraint(:projects, :projects_archived_held,
             check: """
               key IS NOT NULL OR state <> 'archived'
             """
           )

    create constraint(:account_ens_identities, :account_ens_identities_lookup_state,
             check: """
               lookup_state IN ('pending', 'done', 'failed')
             """
           )
  end

  def down do
    drop_if_exists(constraint(:account_ens_identities, :account_ens_identities_lookup_state))

    drop_if_exists(constraint(:projects, :projects_archived_held))

    drop_if_exists(
      constraint(:notebook_saved_outputs, :notebook_saved_outputs_succeeded_or_failed)
    )

    drop_if_exists(constraint(:key_pictures, :key_pictures_small_card_made_or_failed))

    drop_if_exists(constraint(:key_pictures, :key_pictures_close_up_made_or_failed))
  end
end
