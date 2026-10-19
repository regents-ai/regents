defmodule RegentsWeb.PublicRegentController do
  @moduledoc "The existing public Regent profile, through its field-limited Ash action."
  use RegentsWeb, :controller

  alias Regents.Formation

  @fields [:slug, :display_name, :summary, :avatar_url, :verified_wallet_address]
  @errors %{
    "invalid_query" =>
      {400, "This public profile read takes no query parameters.",
       "Use a known public Regent slug without query parameters."},
    "invalid_slug" =>
      {400, "That public Regent slug is not valid.",
       "Use 1 to 63 lowercase letters, numbers and single hyphens between words."},
    "profile_not_found" =>
      {404, "That public Regent profile does not exist.",
       "Use the slug from an existing /regents/ profile page."},
    "profile_unavailable" =>
      {503, "That public Regent profile could not be read.", "Try again in a moment."}
  }

  def show(conn, %{"slug" => slug}) do
    cond do
      map_size(conn.query_params) != 0 ->
        refuse(conn, "invalid_query")

      byte_size(slug) not in 1..63 or not Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, slug) ->
        refuse(conn, "invalid_slug")

      true ->
        case Formation.get_public_regent_profile(slug) do
          {:ok, nil} -> refuse(conn, "profile_not_found")
          {:ok, profile} -> json(conn, %{profile: Map.take(profile, @fields)})
          {:error, _} -> refuse(conn, "profile_unavailable")
        end
    end
  end

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
