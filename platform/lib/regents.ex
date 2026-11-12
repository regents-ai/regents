defmodule Regents do
  @moduledoc """
  Regents keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Whether the signed-in account, or the admin actor acting for it, is one of the
  site's admins (`config :regents, :admins`).
  """
  def admin?(%{privy_user_id: id}), do: id in Application.fetch_env!(:regents, :admins)
  def admin?(_nobody), do: false
end
