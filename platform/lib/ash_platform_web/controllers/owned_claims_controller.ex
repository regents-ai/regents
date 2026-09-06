defmodule AshPlatformWeb.OwnedClaimsController do
  use AshPlatformWeb, :controller

  def index(conn, params) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("vary", "Authorization, Privy-Id-Token")

    with {["Bearer " <> access], [identity]} <-
           {get_req_header(conn, "authorization"), get_req_header(conn, "privy-id-token")},
         true <- byte_size(access) in 1..32_768 and byte_size(identity) in 1..32_768,
         {:ok, actor} <-
           RegentPrivy.Session.verify(
             %{access: access, identity: identity},
             Application.get_env(:ash_platform, :privy, [])
           ),
         true <- get_req_header(conn, "x-privy-user-id") in [[], [actor.privy_user_id]] do
      case pagination(params) do
        {:ok, page} -> render_claims(conn, actor, page)
        :error -> conn |> put_status(400) |> json(%{error: %{code: "invalid_claims_query"}})
      end
    else
      {:error, {:configuration, _}} ->
        conn |> put_status(503) |> json(%{error: %{code: "claims_unconfigured"}})

      _ ->
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
