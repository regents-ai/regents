defmodule Regents.Products do
  @moduledoc """
  The products this one site serves: the one list of them. Each is known by its
  lowercase name, which is also its address (`/<name>` for its pages,
  `/api/v1/<name>` for its API) and its namespace (`Regents.<Name>`);
  everything that is regents.sh's own is `regents`.

  The list names, for each product, the cores whose `health/0` answer for it and
  the schema its own tables live in beside regents.sh's own `regents_app` (`nil`
  when it has none). The health page (`/api/v1/health`), the visit lines'
  `product` field and the release's migrations (`Regents.Release`) all read it.
  """
  use Boundary,
    top_level?: true,
    deps: [
      Regents,
      Regents.Stake,
      Regents.Redeem,
      Regents.Cloak,
      Regents.Techtree,
      Regents.Keyfleet,
      Regents.Autolaunch,
      Regents.Patchbay
    ],
    exports: [AccountOverview]

  @site "regents"

  # The one list. A function, not an attribute, so naming a core here is not a
  # compile-time dependency on it.
  defp products do
    [
      %{
        name: @site,
        health: [&Regents.Account.health/0, &Regents.Stake.health/0, &Regents.Redeem.health/0],
        schema: nil
      },
      %{name: "cloak", health: [&Regents.Cloak.health/0], schema: nil},
      %{name: "techtree", health: [&Regents.Techtree.health/0], schema: "techtree_app"},
      %{name: "keyfleet", health: [&Regents.Keyfleet.health/0], schema: "keyfleet_app"},
      %{name: "autolaunch", health: [&Regents.Autolaunch.health/0], schema: "autolaunch_app"},
      %{name: "patchbay", health: [&Regents.Patchbay.health/0], schema: "patchbay_app"}
    ]
  end

  # One second, like the database check before it: a slow product answers
  # `unavailable` at this bound without holding up the others.
  @health_timeout 1_000

  @doc "Every product's name, regents.sh's own first."
  def names, do: Enum.map(products(), & &1.name)

  @doc "Each product with tables of its own, as `{name, schema}`, in the order their migrations apply."
  def schemas,
    do:
      for(%{name: name, schema: schema} when is_binary(schema) <- products(), do: {name, schema})

  @doc """
  Every area of the database this release migrates, as `{schema, migrations folder}`,
  in the order they apply: regents.sh's own (`regents_app`, `priv/repo/migrations`),
  then each product's from `schemas/0` (`priv/<name>/migrations`), each with its
  own ledger `<schema>.schema_migrations`.
  """
  def migration_areas do
    [
      {Regents.Repo.default_prefix(), Application.app_dir(:regents, "priv/repo/migrations")}
      | for(
          {name, schema} <- schemas(),
          do: {schema, Application.app_dir(:regents, "priv/#{name}/migrations")}
        )
    ]
  end

  @doc """
  The product an address belongs to: the first part of its path, or the part
  after `/api/v1/`, when that is a product's name; otherwise `regents`.
  """
  def for_path(path) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      ["api", "v1", name | _rest] -> named(name)
      ["api", "agent", "v1", name | _rest] -> named(name)
      [name | _rest] -> named(name)
      [] -> @site
    end
  end

  @doc "The product a module belongs to, by its namespace: `Regents.Techtree.*` is `techtree`."
  def for_module(module) when is_binary(module) do
    case String.split(module, ".") do
      ["Regents", namespace | _rest] -> named(Macro.underscore(namespace))
      _other -> @site
    end
  end

  defp named(name), do: if(name in names(), do: name, else: @site)

  @doc """
  Each product's health by name, `"ok"` or `"unavailable"`. A product is `ok`
  only when every one of its cores' `health/0` answers `:ok` within the bound;
  all of them are asked at once, and one that fails, raises or is slow makes
  only its own product `unavailable`. No reason leaves this function.
  """
  def health do
    checks = for %{name: name, health: checks} <- products(), check <- checks, do: {name, check}

    __MODULE__.Health
    |> Task.Supervisor.async_stream_nolink(checks, fn {_name, check} -> check.() end,
      timeout: @health_timeout,
      on_timeout: :kill_task,
      max_concurrency: length(checks)
    )
    |> Enum.zip_with(checks, fn answer, {name, _check} -> {name, answer == {:ok, :ok}} end)
    |> Enum.group_by(fn {name, _ok?} -> name end, fn {_name, ok?} -> ok? end)
    |> Map.new(fn {name, answers} ->
      {name, if(Enum.all?(answers), do: "ok", else: "unavailable")}
    end)
  end
end
