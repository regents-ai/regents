defmodule AshPlatformWeb.ProductsController do
  @moduledoc "The product directory, as the product pages show it."
  use AshPlatformWeb, :controller

  alias AshPlatformWeb.ProductDirectory

  def index(conn, params) when map_size(params) == 0,
    do: json(conn, %{products: ProductDirectory.list()})

  def index(conn, _params), do: invalid_query(conn)

  def show(conn, %{"slug" => slug} = params) when map_size(params) == 1 do
    case ProductDirectory.fetch(slug) do
      {:ok, product} ->
        json(conn, %{product: product})

      :error ->
        conn
        |> put_status(404)
        |> json(%{
          error: %{
            code: "product_not_found",
            message: "Use one of: #{Enum.join(ProductDirectory.slugs(), ", ")}."
          }
        })
    end
  end

  def show(conn, _params), do: invalid_query(conn)

  defp invalid_query(conn),
    do:
      conn
      |> put_status(400)
      |> json(%{error: %{code: "invalid_query", message: "This read takes no query parameters."}})
end
