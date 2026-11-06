defmodule Regents do
  @moduledoc """
  Regents keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc "Whether the signed-in account is one of the site's admins (`config :regents, :admins`)."
  def admin?(nil), do: false
  def admin?(account), do: account.privy_user_id in Application.fetch_env!(:regents, :admins)
end
