defmodule RegentsWeb.OwnedClaimsController do
  use RegentsWeb, :controller

  def index(conn, params) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("vary", "Authorization, Privy-Id-Token")

    case RegentsWeb.PrivyPair.verify(conn) do
      {:ok, actor} ->
        case pagination(params) do
          {:ok, page} -> render_claims(conn, actor, page)
          :error -> error(conn, "invalid_claims_query")
        end

      {:error, :unconfigured} ->
        error(conn, "claims_unconfigured")

      {:error, :unauthenticated} ->
        error(conn, "authentication_required")
    end
  end

  defp pagination(params) when map_size(params) == 0, do: {:ok, []}

  defp pagination(%{"after" => cursor} = params)
       when map_size(params) == 1 and is_binary(cursor) and byte_size(cursor) in 1..2048,
       do: {:ok, [after: cursor]}

  defp pagination(_), do: :error

  defp render_claims(conn, actor, page) do
    case Regents.Names.list_my_claims(actor: actor, page: page) do
      {:ok, result} ->
        json(conn, %{
          claims: Enum.map(result.results, &Regents.Names.present/1),
          next: if(result.more?, do: List.last(result.results).__metadata__.keyset, else: nil)
        })

      {:error, %{class: :forbidden}} ->
        error(conn, "claims_forbidden")

      {:error, %{class: :invalid}} ->
        error(conn, "invalid_cursor")

      {:error, _} ->
        error(conn, "claims_unavailable")
    end
  end

  # Every refusal: a code for programs, a message and a hint for people.
  @errors %{
    "invalid_claims_query" =>
      {400, "This read takes no query parameters other than after.",
       "Send no query for the first page, then after= with the next value from the page before."},
    "claims_unconfigured" => {503, "Sign-in checks are not set up here.", "Try again later."},
    "authentication_required" =>
      {401, "Sign in to read your claims.",
       "Send the Privy access token as a Bearer token and the identity token in privy-id-token, both from the same sign-in."},
    "claims_forbidden" =>
      {403, "This sign-in can't read these claims.", "Sign in again, then retry."},
    "invalid_cursor" =>
      {400, "The after value isn't one this read gave out.",
       "Start again without after, then follow each page's next value."},
    "claims_unavailable" =>
      {503, "Your claims couldn't be read right now.", "Try again in a moment."}
  }

  defp error(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
