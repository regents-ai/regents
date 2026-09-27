defmodule RegentsWeb.ProductDirectory do
  @moduledoc """
  The Regents product directory: what the /autolaunch, /techtree and /patchbay
  pages show, read from the same content those pages render.
  """

  alias RegentsWeb.{AutolaunchLive, ProductLive, PublicDocuments}

  @slugs ~w(autolaunch techtree patchbay)
  @listed [:slug, :name, :summary, :site, :page, :github]

  def slugs, do: @slugs

  @doc "Every product, in the order the site lists them."
  def list, do: Enum.map(@slugs, &(&1 |> product() |> Map.take(@listed)))

  @doc "Everything one product's page shows."
  def fetch(slug) when slug in @slugs, do: {:ok, product(slug)}
  def fetch(_slug), do: :error

  defp product("autolaunch"), do: with_page(AutolaunchLive.content(), "autolaunch")
  defp product("techtree"), do: with_page(ProductLive.content(:techtree), "techtree")
  defp product("patchbay"), do: with_page(ProductLive.content(:patchbay), "patchbay")

  defp with_page(content, slug),
    do: Map.merge(content, %{slug: slug, page: PublicDocuments.url("/" <> slug)})
end
