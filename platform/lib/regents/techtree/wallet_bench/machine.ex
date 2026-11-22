defmodule Regents.Techtree.WalletBench.Machine do
  @moduledoc """
  One machine techtree.sh's bench tests on. A test's page reads only its
  baseline's `manifest.json`: the harness's version, the model and its
  reasoning effort, and the machine's system.

  Read only here: only the columns the pages read are attributes.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.WalletBench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Techtree's own area of the shared database, where techtree.sh's bench writes
  # these rows; their migrations stay techtree.sh's.
  postgres do
    table "wallet_bench_machines"
    schema("techtree_app")
    repo(Regents.Repo)
    migrate?(false)
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :manifest, :map,
      public?: true,
      description: "The baseline's `manifest.json`: harness, translator, model and image facts."
  end
end
