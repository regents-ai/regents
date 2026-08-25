defmodule AshPlatform.Formation.Regent.Actions.ReadPublicProfile do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.Formation
  alias AshPlatform.Formation.PublicRegentProfile

  @impl true
  def run(input, _opts, _context) do
    slug = input.arguments.slug
    system = %System{}

    with {:ok, regent} when not is_nil(regent) <- Formation.get_public_regent(slug),
         {:ok, account} when not is_nil(account) <-
           Accounts.get_public_profile_source(regent.human_account_id, actor: system),
         {:ok, runtime} <-
           Formation.get_public_cloud_profile_source(regent.id, actor: system) do
      {:ok,
       %PublicRegentProfile{
         slug: regent.slug,
         display_name: regent.display_name,
         summary: regent.summary,
         avatar_url: regent.avatar_url,
         verified_wallet_address: account.wallet_address,
         cloud_connected?: not is_nil(runtime)
       }}
    end
  end
end
