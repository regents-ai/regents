defmodule AshPlatformWeb.Showcase.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshPlatformWeb.Showcase.Sample
  end
end

defmodule AshPlatformWeb.Showcase.Sample do
  @moduledoc "Local, data-layer-less resource. Its records never reach Postgres."
  use Ash.Resource,
    domain: AshPlatformWeb.Showcase.Domain,
    data_layer: Ash.DataLayer.Simple,
    authorizers: [Ash.Policy.Authorizer]

  resource do
    require_primary_key? false
  end

  policies do
    # The workshop has no signed-in actor and this resource holds no data: each
    # record lives only in the loopback-only LiveView that created it. Reaching
    # the route is the boundary; the policy states that openly instead of
    # skipping authorization at each call.
    policy action(:create) do
      authorize_if always()
    end
  end

  attributes do
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :quantity, :integer, default: 1, public?: true
  end

  actions do
    create :create do
      accept [:title, :quantity]
      validate string_length(:title, min: 2, max: 80)
      validate numericality(:quantity, greater_than: 0, less_than_or_equal_to: 100)
    end
  end
end
