defmodule AshPlatformWeb.Showcase.Catalog do
  @moduledoc "The showcase's explicit visual coverage and executable API inventory."

  @components [
    {Regent.Primitives, [:button, :field, :status, :notice, :empty_state, :disclosure]},
    {Regent.Panels, [:chamber, :ledger]},
    {Regent.BackgroundGrid, [:background_grid]},
    {AshPlatformWeb.Components.Background, [:background]},
    {AshPlatformWeb.Components.Shell, [:shell, :theme_toggle]},
    {AshPlatformWeb.Components.CommentLedger, [:comment_ledger]},
    {AshPlatformWeb.Components.VerifiedConnections, [:verified_connections]},
    {AshPlatformWeb.Layouts, [:app, :root]}
  ]
  @aliases [
    {Regent.Chamber, :chamber, Regent.Panels},
    {Regent.Ledger, :ledger, Regent.Panels}
  ]
  def registry, do: @components

  def aliases,
    do:
      Enum.map(@aliases, fn {module, name, target} ->
        %{name: "#{inspect(module)}.#{name}/1", target: "#{inspect(target)}.#{name}/1"}
      end)

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
      if Code.ensure_loaded?(module) and function_exported?(module, :__info__, 1) do
        functions =
          module.__info__(:functions)
          |> Enum.reject(fn {name, _} -> String.starts_with?(Atom.to_string(name), "__") end)

        if functions == [],
          do: [],
          else: [
            %{
              name: inspect(module),
              owner: owner,
              functions: Enum.map(functions, fn {name, arity} -> "#{name}/#{arity}" end)
            }
          ]
      else
        []
      end
    end)
  end

  def snapshot,
    do: %{
      components: components(),
      aliases: aliases(),
      domains: domains(),
      utilities: utilities(),
      ash_phoenix_installed: Code.ensure_loaded?(AshPhoenix.Form)
    }
end

defmodule AshPlatformWeb.Showcase.CatalogController do
  use AshPlatformWeb, :controller

  def style(conn, _params),
    do:
      conn
      |> put_resp_content_type("text/css")
      |> send_file(200, Application.app_dir(:ash_platform, "priv/showcase.css"))

  def show(conn, _params), do: json(conn, AshPlatformWeb.Showcase.Catalog.snapshot())
end
