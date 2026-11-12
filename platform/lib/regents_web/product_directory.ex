defmodule RegentsWeb.ProductDirectory do
  @moduledoc """
  The Regents product directory: what the /keyfleet, /autolaunch, /patchbay and
  /techtree pages show, read from the same content those pages render.
  """

  alias RegentsWeb.{AutolaunchLive, ProductLive, PublicDocuments}

  @slugs ~w(keyfleet autolaunch patchbay techtree)
  @listed [:slug, :name, :summary, :site, :page, :github]
  # A card's words and where it goes; its picture and colour are the page's own.
  @card_words [:name, :headline, :line, :action, :href]

  def slugs, do: @slugs

  @doc "Every product, in the order the site lists them."
  def list, do: Enum.map(@slugs, &(&1 |> product() |> Map.take(@listed)))

  @doc "Everything one product's page shows."
  def fetch(slug) when slug in @slugs, do: {:ok, product(slug)}
  def fetch(_slug), do: :error

  defp product("autolaunch"), do: with_page(AutolaunchLive.content(), "autolaunch")
  defp product("techtree"), do: with_page(ProductLive.content(:techtree), "techtree")
  defp product("patchbay"), do: with_page(ProductLive.content(:patchbay), "patchbay")
  defp product("keyfleet"), do: with_page(ProductLive.content(:keyfleet), "keyfleet")

  defp with_page(content, slug) do
    Map.merge(content, %{
      slug: slug,
      page: PublicDocuments.url("/" <> slug),
      cards: Enum.map(content.cards, &Map.take(&1, @card_words))
    })
  end
end
