defmodule RegentIdentity.HTTP do
  @moduledoc """
  Owner-only profile HTTP adapter, mounted by each product at `/api/v1/profile`.
  Requires an explicit Privy proof pair on every request; never trusts cookies or
  caller-supplied actor IDs. Products keep their own session and payment routes.
  """
  @behaviour Plug
  import Plug.Conn

  # Every refusal answers {error: {code, message, hint}}: what went wrong, and
  # what the caller can do next.
  @errors %{
    "authentication_required" =>
      {"Sign in to read or change your profile.",
       "Send the access token as a Bearer token and the identity token in privy-id-token, both from the same sign-in."},
    "identity_evidence_conflict" =>
      {"Your sign-in could not be matched to your profile.", "Sign in again, then retry."},
    "invalid_profile_json" => {"The request body is not valid JSON.", "Send one JSON object."},
    "invalid_profile_update" =>
      {"The profile change could not be made.",
       "Send only display_name and wallet_address, where wallet_address is a wallet linked to your sign-in. If your profile changed, read it again first."},
    "json_required" =>
      {"Profile changes must be sent as JSON.", "Set Content-Type to application/json."},
    "method_not_allowed" =>
      {"This route does not accept that method.", "Use a method listed in the Allow header."},
    "not_found" =>
      {"There is no profile route here.", "Use /api/v1/profile or /api/v1/profile/sync."},
    "profile_forbidden" =>
      {"This profile belongs to another account.", "Sign in as the profile's owner."},
    "profile_not_created" =>
      {"You have no profile yet.", "Create it with POST /api/v1/profile/sync."},
    "profile_request_too_large" =>
      {"The request body is too large.",
       "Send only display_name and wallet_address, in under 8 KB."},
    "profile_unavailable" =>
      {"Your profile could not be reached right now.", "Try again in a moment."},
    "profile_unconfigured" =>
      {"Profiles are not available on this site right now.", "Try again later."}
  }

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :otp_app)

  @impl true
  def call(conn, otp_app) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")

    with {:ok, pair} <- proof(conn),
         {:ok, actor} <-
           RegentPrivy.Session.verify(pair, Application.get_env(otp_app, :privy, [])),
         :ok <- expected_subject(conn, actor) do
      dispatch(conn, actor)
    else
      {:error, {:configuration, _}} ->
        error(conn, 503, "profile_unconfigured")

      {:error, _} ->
        error(conn, 401, "authentication_required")
    end
  rescue
    Plug.Parsers.ParseError ->
      error(conn, 400, "invalid_profile_json")

    Plug.Parsers.RequestTooLargeError ->
      error(conn, 413, "profile_request_too_large")

    Plug.Parsers.UnsupportedMediaTypeError ->
      error(conn, 415, "json_required")
  end

  # This optional browser binding can only restrict valid proof. It never
  # supplies an actor or grants access to the subject named in the header.
  defp expected_subject(conn, actor) do
    case get_req_header(conn, "x-privy-user-id") do
      [] -> :ok
      [subject] when subject == actor.privy_user_id -> :ok
      _ -> {:error, :subject_changed}
    end
  end

  defp proof(conn) do
    case {get_req_header(conn, "authorization"), get_req_header(conn, "privy-id-token")} do
      {["Bearer " <> access], [identity]}
      when byte_size(access) in 1..32768 and byte_size(identity) in 1..32768 ->
        {:ok, %{access: access, identity: identity}}

      _ ->
        {:error, :missing_proof}
    end
  end

  defp dispatch(%{method: "GET", path_info: []} = conn, actor) do
    case RegentIdentity.get_my_profile(actor: actor) do
      {:ok, nil} -> error(conn, 404, "profile_not_created")
      {:ok, profile} -> answer(conn, 200, %{profile: RegentIdentity.present(profile)})
      {:error, error} -> failure(conn, error, 403, "profile_forbidden")
    end
  end

  defp dispatch(%{method: "POST", path_info: ["sync"]} = conn, actor) do
    case RegentIdentity.sync(actor) do
      {:ok, profile} -> answer(conn, 200, %{profile: RegentIdentity.present(profile)})
      {:error, error} -> failure(conn, error, 409, "identity_evidence_conflict")
    end
  end

  defp dispatch(%{method: "PATCH", path_info: []} = conn, actor) do
    if json_request?(conn) do
      edit(conn, actor)
    else
      error(conn, 415, "json_required")
    end
  end

  defp dispatch(%{path_info: path} = conn, _actor) when path in [[], ["sync"]] do
    methods = if path == [], do: "GET, PATCH", else: "POST"

    conn
    |> put_resp_header("allow", methods)
    |> error(405, "method_not_allowed")
  end

  defp dispatch(conn, _actor), do: error(conn, 404, "not_found")

  defp edit(conn, actor) do
    conn =
      Plug.Parsers.call(
        conn,
        Plug.Parsers.init(parsers: [:json], json_decoder: Jason, length: 8192)
      )

    with true <-
           is_map(conn.body_params) and map_size(conn.body_params) > 0 and
             Enum.all?(Map.keys(conn.body_params), &(&1 in ["display_name", "wallet_address"])),
         {:ok, profile} when not is_nil(profile) <- RegentIdentity.get_my_profile(actor: actor),
         true <- expected_profile?(conn, profile),
         {:ok, updated} <- RegentIdentity.edit_profile(profile, conn.body_params, actor: actor) do
      answer(conn, 200, %{profile: RegentIdentity.present(updated)})
    else
      {:error, error} -> failure(conn, error, 422, "invalid_profile_update")
      _ -> error(conn, 422, "invalid_profile_update")
    end
  end

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
