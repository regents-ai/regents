defmodule AshPlatform.Formation.PublicRegentProfile do
  @moduledoc "Field-limited public projection for one Regent profile."

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  attributes do
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :display_name, :string, allow_nil?: false, public?: true
    attribute :summary, :string, public?: true
    attribute :avatar_url, :string, public?: true
    attribute :verified_wallet_address, :string, public?: true
    attribute :cloud_connected?, :boolean, allow_nil?: false, default: false, public?: true
  end
end
