defmodule RegentIdentity.HTTP do
  @moduledoc """
  The profile API, mounted by each product at `/api/v1/profile`. It acts for the
  owner the product put on the request with `put_owner/2`: the product decides
  who is calling from its own sign-in, such as its session or an agent the
  person paired, in a plug before this one. With no owner it answers
  `authentication_required`. It reads no credential or person from the request
  itself. Products keep their own session and payment routes.
  """
  @behaviour Plug
  import Plug.Conn

  alias RegentIdentity.Owner

  # Every refusal answers {error: {code, message, hint}}: what went wrong, and
  # what the caller can do next.
  @errors %{
    "authentication_required" =>
      {"Sign in to read or change your profile.",
       "Sign in on this site, or have an agent you paired send the request, signed with its own key."},
    "invalid_display_name" =>
      {"That name can't be used.",
       "Send a display_name of at most 80 characters with no hidden characters: no control, line-break, text-direction or zero-width characters, except a zero-width joiner between two visible characters, as in an emoji."},
    "invalid_profile_json" => {"The request body is not valid JSON.", "Send one JSON object."},
    "invalid_profile_update" =>
      {"The profile change could not be made.",
       "Send only display_name and wallet_address, where wallet_address is a wallet linked to your sign-in. If your profile changed, read it again first."},
    "json_required" =>
      {"Profile changes must be sent as JSON.", "Set Content-Type to application/json."},
    "method_not_allowed" =>
      {"This route does not accept that method.", "Use a method listed in the Allow header."},
    "not_found" => {"There is no profile route here.", "Use /api/v1/profile."},
    "profile_forbidden" =>
      {"This profile belongs to another account.", "Sign in as the profile's owner."},
    "profile_not_created" =>
      {"You have no profile yet.",
       "It is made when you sign in on this site. Sign in, then try again."},
    "profile_request_too_large" =>
      {"The request body is too large.",
       "Send only display_name and wallet_address, in under 8 KB."},
    "profile_unavailable" =>
      {"Your profile could not be reached right now.", "Try again in a moment."}
  }

  @doc "Puts the profile's owner on the request, for this API to act for."
  @spec put_owner(Plug.Conn.t(), Owner.t()) :: Plug.Conn.t()
  def put_owner(conn, %Owner{} = owner), do: put_private(conn, :regent_identity_owner, owner)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")

    case conn.private do
      %{regent_identity_owner: %Owner{} = owner} -> dispatch(conn, owner)
      _no_owner -> error(conn, 401, "authentication_required")
    end
  rescue
    Plug.Parsers.ParseError ->
      error(conn, 400, "invalid_profile_json")

    Plug.Parsers.RequestTooLargeError ->
      error(conn, 413, "profile_request_too_large")

    Plug.Parsers.UnsupportedMediaTypeError ->
      error(conn, 415, "json_required")
  end

  defp dispatch(%{method: "GET", path_info: []} = conn, owner) do
    case RegentIdentity.get_my_profile(actor: owner) do
      {:ok, nil} -> error(conn, 404, "profile_not_created")
      {:ok, profile} -> answer(conn, 200, %{profile: RegentIdentity.present(profile)})
      {:error, error} -> failure(conn, error, 403, "profile_forbidden")
    end
  end

  defp dispatch(%{method: "PATCH", path_info: []} = conn, owner) do
    if json_request?(conn) do
      edit(conn, owner)
    else
      error(conn, 415, "json_required")
    end
  end

  defp dispatch(%{path_info: []} = conn, _owner) do
    conn
    |> put_resp_header("allow", "GET, PATCH")
    |> error(405, "method_not_allowed")
  end

  defp dispatch(conn, _owner), do: error(conn, 404, "not_found")

  defp edit(conn, owner) do
    conn =
      Plug.Parsers.call(
        conn,
        Plug.Parsers.init(parsers: [:json], json_decoder: Jason, length: 8192)
      )

    with true <-
           is_map(conn.body_params) and map_size(conn.body_params) > 0 and
             Enum.all?(Map.keys(conn.body_params), &(&1 in ["display_name", "wallet_address"])),
         {:ok, profile} when not is_nil(profile) <- RegentIdentity.get_my_profile(actor: owner),
         true <- expected_profile?(conn, profile),
         {:ok, updated} <- RegentIdentity.edit_profile(profile, conn.body_params, actor: owner) do
      answer(conn, 200, %{profile: RegentIdentity.present(updated)})
    else
      {:error, error} -> failure(conn, error, 422, edit_refusal(error))
      _ -> error(conn, 422, "invalid_profile_update")
    end
  end

  defp edit_refusal(%Ash.Error.Invalid{errors: errors}) do
    if Enum.any?(errors, &match?(%{field: :display_name}, &1)),
      do: "invalid_display_name",
      else: "invalid_profile_update"
  end

  defp edit_refusal(_error), do: "invalid_profile_update"

  defp expected_profile?(conn, profile) do
    case get_req_header(conn, "x-regent-profile-id") do
      [] -> true
      [id] -> id == profile.id
      _ -> false
    end
  end

  defp json_request?(conn) do
    case get_req_header(conn, "content-type") do
      [type] ->
        type |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase() ==
          "application/json"

      _ ->
        false
    end
  end

  defp failure(conn, %{class: :forbidden}, _status, _code),
    do: error(conn, 403, "profile_forbidden")

  defp failure(conn, %{class: :invalid}, status, code),
    do: error(conn, status, code)

  defp failure(conn, _error, _status, _code),
    do: error(conn, 503, "profile_unavailable")

  defp error(conn, status, code) do
    {message, hint} = Map.fetch!(@errors, code)
    answer(conn, status, %{error: %{code: code, message: message, hint: hint}})
  end

  defp answer(conn, status, body),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(body))
      |> halt()
end
