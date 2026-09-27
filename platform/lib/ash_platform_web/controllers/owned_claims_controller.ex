defmodule AshPlatformWeb.OwnedClaimsController do
  use AshPlatformWeb, :controller

  def index(conn, params) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("vary", "Authorization, Privy-Id-Token")

    case AshPlatformWeb.PrivyPair.verify(conn) do
      {:ok, actor} ->
        case pagination(params) do
          {:ok, page} -> render_claims(conn, actor, page)
          :error -> conn |> put_status(400) |> json(%{error: %{code: "invalid_claims_query"}})
        end

      {:error, :unconfigured} ->
        conn |> put_status(503) |> json(%{error: %{code: "claims_unconfigured"}})

      {:error, :unauthenticated} ->
        conn |> put_status(401) |> json(%{error: %{code: "authentication_required"}})
    end
  end

  defp pagination(params) when map_size(params) == 0, do: {:ok, []}

  defp pagination(%{"after" => cursor} = params)
       when map_size(params) == 1 and is_binary(cursor) and byte_size(cursor) in 1..2048,
       do: {:ok, [after: cursor]}

  defp pagination(_), do: :error

  defp render_claims(conn, actor, page) do
    case AshPlatform.Names.list_my_claims(actor: actor, page: page) do
      {:ok, result} ->
        json(conn, %{
          claims: Enum.map(result.results, &AshPlatform.Names.present/1),
          next: if(result.more?, do: List.last(result.results).__metadata__.keyset, else: nil)
        })

      {:error, %{class: :forbidden}} ->
        conn |> put_status(403) |> json(%{error: %{code: "claims_forbidden"}})

      {:error, %{class: :invalid}} ->
        conn |> put_status(400) |> json(%{error: %{code: "invalid_cursor"}})

      {:error, _} ->
        conn |> put_status(503) |> json(%{error: %{code: "claims_unavailable"}})
    end
  end
end
