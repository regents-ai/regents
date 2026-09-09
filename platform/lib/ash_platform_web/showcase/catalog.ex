defmodule AshPlatformWeb.Showcase.Catalog do
  @moduledoc "The showcase's explicit visual coverage and executable API inventory."

  @components [
    {Regent.Primitives, [:button, :field, :status, :notice, :empty_state, :disclosure]},
    {Regent.Structure,
     [:frame, :row, :section_bar, :panel, :technical_figure, :capability_card, :ratio_card]},
    {Regent.Blog, [:gallery, :article, :contents, :not_found]},
    {Regent.ThemeToggle, [:button]},
    {AshPlatformWeb.Components.Shell, [:shell, :account_control, :theme_toggle]},
    {AshPlatformWeb.Components.CommentLedger, [:comment_ledger]},
    {AshPlatformWeb.Components.VerifiedConnections, [:verified_connections]},
    {AshPlatformWeb.Layouts, [:app, :root]}
  ]
  def registry, do: @components

  def components do
    for {module, names} <- @components, name <- names do
      Code.ensure_loaded!(module)

      info =
        if function_exported?(module, :__components__, 0),
          do: Map.get(module.__components__(), name, %{}),
          else: %{}

      %{
        module: inspect(module),
        function: Atom.to_string(name),
        attributes: Enum.map(Map.get(info, :attrs, []), &Atom.to_string(&1.name)),
        slots: Enum.map(Map.get(info, :slots, []), &Atom.to_string(&1.name))
      }
    end
  end

  def domains do
    for domain <- Application.get_env(:ash_platform, :ash_domains, []) do
      %{
        name: inspect(domain),
        resources:
          Enum.map(Ash.Domain.Info.resources(domain), fn resource ->
            %{
              name: inspect(resource),
              attributes:
                Enum.map(
                  Ash.Resource.Info.attributes(resource),
                  &%{name: &1.name, public: &1.public?}
                ),
              actions:
                Enum.map(Ash.Resource.Info.actions(resource), &%{name: &1.name, type: &1.type})
            }
          end)
      }
    end
  end

  def utilities do
    shared =
      for app <- [:regent_privy, :ens_elixir],
          module <- Application.spec(app, :modules) || [],
          do: {module, "Shared library"}

    product =
      for module <- Application.spec(:ash_platform, :modules) || [],
          String.starts_with?(inspect(module), [
            "AshPlatform.WalletActions.",
            "AshPlatform.DatabaseConfig",
            "AshPlatform.Staking.",
            "AshPlatform.Redemption."
          ]),
          do: {module, "Regents-owned"}

    (shared ++ product)
    |> Enum.uniq()
    |> Enum.sort_by(fn {module, _} -> inspect(module) end)
    |> Enum.flat_map(fn {module, owner} ->
      case exported_functions(module) do
        [] -> []
        functions -> [%{name: inspect(module), owner: owner, functions: functions}]
      end
    end)
  end

  defp exported_functions(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__info__, 1) do
      for {name, arity} <- module.__info__(:functions),
          not String.starts_with?(Atom.to_string(name), "__"),
          do: "#{name}/#{arity}"
    else
      []
    end
  end

  def snapshot,
    do: %{
      components: components(),
      domains: domains(),
      utilities: utilities(),
      ash_phoenix_installed: Code.ensure_loaded?(AshPhoenix.Form)
    }
end

defmodule AshPlatformWeb.Showcase.CatalogController do
  use AshPlatformWeb, :controller

  # The path is the fixed priv stylesheet; no request value reaches send_file.
  # sobelow_skip ["Traversal.SendFile"]
  def style(conn, _params),
    do:
      conn
      |> put_resp_content_type("text/css")
      |> send_file(200, Application.app_dir(:ash_platform, "priv/showcase.css"))

  def show(conn, _params), do: json(conn, AshPlatformWeb.Showcase.Catalog.snapshot())
end
