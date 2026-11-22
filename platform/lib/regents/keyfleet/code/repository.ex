defmodule Regents.Keyfleet.Code.Repository do
  @moduledoc """
  A project's repository in the code store, as this site made it, by its
  name (`Regents.Keyfleet.Projects.Project`, `repository`): the owner the store keeps
  it under, which every address in the store names. Recorded once, when the
  repository is made (`Regents.Keyfleet.Code.Setup`), and forgotten once the store
  has deleted it with its project (`Regents.Keyfleet.Code.DeleteRepository`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Code,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "code_repositories"
    schema("keyfleet_app")
    repo(Regents.Repo)
  end

  actions do
    defaults [:read]

    create :record do
      accept [:repository, :owner]
    end

    destroy :forget
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :repository, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :owner, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end
end
