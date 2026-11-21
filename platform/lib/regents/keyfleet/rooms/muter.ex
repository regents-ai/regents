defmodule Regents.Keyfleet.Rooms.Muter do
  @moduledoc """
  Who a mute belongs to, as it is stored: `human:<account id>` for a person
  signed in, `agent:<wallet>` for an agent signed in with its wallet, and nil
  for anyone else, who has no mutes.
  """

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.Human

  @doc "The muter `actor` is, or nil."
  def of(%Human{human_account_id: id}) when is_integer(id), do: "human:#{id}"

  def of(%Agent{wallet_address: wallet} = actor),
    do: if(Agent.valid?(actor), do: "agent:" <> wallet)

  def of(_actor), do: nil

  @doc "Where one muter's own pages hear that its mutes in a fleet changed."
  def topic(muter), do: "keyfleet:mutes:" <> muter
end
