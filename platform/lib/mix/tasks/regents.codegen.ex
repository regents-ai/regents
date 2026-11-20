defmodule Mix.Tasks.Regents.Codegen do
  @moduledoc """
  `mix ash.codegen`, once for regents.sh's own domains and once for each folded
  product's (`Regents.Release.products/0`), so each keeps its migrations and
  snapshots in its own folders (`priv/repo/` and `priv/<product>/`). Takes
  `ash.codegen`'s arguments; `mix ash.codegen` runs this.
  """
  use Boundary, classify_to: Regents.Release

  use Mix.Task

  @shortdoc "Runs ash.codegen for regents.sh and each folded product"

  @impl true
  def run(args) do
    Mix.Task.run("compile")
    domains = Application.fetch_env!(:regents, :ash_domains)

    products =
      for {product, _schema} <- Regents.Release.products() do
        namespace = ["Regents", Macro.camelize(product)]
        {product, Enum.filter(domains, &(Enum.take(Module.split(&1), 2) == namespace))}
      end

    site = domains -- Enum.flat_map(products, &elem(&1, 1))
    Mix.Tasks.Ash.Codegen.run(args ++ ["--domains", Enum.map_join(site, ",", &inspect/1)])

    # An empty `--domains` means every domain, so a product with none yet is skipped.
    for {product, [_ | _] = product_domains} <- products do
      Mix.Tasks.Ash.Codegen.run(
        args ++
          [
            "--domains",
            Enum.map_join(product_domains, ",", &inspect/1),
            "--migration-path",
            "priv/#{product}/migrations",
            "--snapshot-path",
            "priv/#{product}/resource_snapshots"
          ]
      )
    end
  end
end
