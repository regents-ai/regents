defmodule Regents.Messages.Message.SetSender do
  @moduledoc """
  Makes the actor the message's sender: a signed-in person, or a paired agent
  with its person. Nothing a caller sends can name the sender. The person's name
  is read as the message is written, as their Account page shows it.
  """

  use Ash.Resource.Change

  alias Regents.Accounts
  alias Regents.Actors.{Agent, Human, System}

  @impl true
  def change(changeset, _opts, %{actor: %Human{human_account_id: id}}),
    do: sender(changeset, id, nil)

  def change(changeset, _opts, %{actor: %Agent{human_account_id: id, wallet_address: wallet}}),
    do: sender(changeset, id, String.downcase(wallet))

  # Anyone else is refused by the action's policy.
  def change(changeset, _opts, _context), do: changeset

  defp sender(changeset, account_id, wallet) do
    changeset
    |> Ash.Changeset.force_change_attributes(
      human_account_id: account_id,
      agent_wallet_address: wallet
    )
    |> Ash.Changeset.before_action(fn changeset ->
      account =
        Accounts.points_account!(account_id, actor: %System{}, load: [:display_name, :ens_name])

      Ash.Changeset.force_change_attribute(
        changeset,
        :sender_name,
        Regents.PublicIdentity.label(account)
      )
    end)
  end
end
