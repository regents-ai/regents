defmodule Regents.Keyfleet.Graph.Listener do
  @moduledoc """
  The graph machine's private door, the one way the site reaches the fleets'
  writers and projectors there (`Regents.Keyfleet.Graph.Client`). It listens on the
  port `:graph_listener` names, which fly.toml declares as no service, so Fly
  sends it no public traffic and only the app's private network reaches it.
  It starts after the writers and stops before them, letting the requests it
  holds finish.

  Every request but the health answer carries a pass for its fleet and its one
  route (`Regents.Keyfleet.Graph.Pass`), checked before its body is read, and a JSON
  body of at most 2 MiB; the graph host refuses any write over 1 MiB, and the
  site's own doors take far less. The routes:

    * `POST /fleets/:fleet/write` and `POST /fleets/:fleet/check` take
      `{"op", "body", "authority"}`, a write operation, its body and the rule
      that decides its authority (`Regents.Keyfleet.Graph.Authority`), and answer what
      the writer answered (`Regents.Keyfleet.Graph.Writer.command/4` and `check/4`) as
      `{"answer": ...}`: `ok` with the host's `reply`, `refused` with the
      host's `refusal`, `not_key_holder` or `edits_restricted` with the
      `token_id`, `ownership_refreshing`, `unavailable` or `indeterminate`.
    * `POST /fleets/:fleet/await` takes `{"run_id", "seq"}` and answers
      `{"watermark": ...}` (`Regents.Keyfleet.Graph.Projector.await/3`).
    * `GET /healthz` answers 200 with no body and runs nothing, so Fly's check
      reads it without a pass.

  A request with no valid pass is answered 401, a malformed one 400, one too
  large 413 and any other address 404, each with nothing run. Nothing a
  request carries names code: the operation is one of the writer's fixed few
  and the rule is matched by its name.
  """

  @behaviour Plug

  import Plug.Conn

  alias Regents.Keyfleet.Graph.Authority
  alias Regents.Keyfleet.Graph.Errors.EditsRestrictedError
  alias Regents.Keyfleet.Graph.Errors.NotKeyHolderError
  alias Regents.Keyfleet.Graph.Pass
  alias Regents.Keyfleet.Graph.Projector
  alias Regents.Keyfleet.Graph.Writer
  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError

  @max_body 2 * 1024 * 1024

  def child_spec(_arg) do
    :regents
    |> Application.fetch_env!(:keyfleet_graph_listener)
    |> Keyword.merge(plug: __MODULE__, startup_log: false)
    |> Bandit.child_spec()
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "GET", path_info: ["healthz"]} = conn, _opts),
    do: send_resp(conn, :ok, "")

  def call(%Plug.Conn{method: "POST", path_info: ["fleets", fleet_id, scope]} = conn, _opts)
      when scope in ~w(write check await) do
    with {:pass, true} <- {:pass, Pass.valid?(bearer(conn), fleet_id, scope)},
         {:ok, body, conn} <- read_body(conn, length: @max_body),
         {:ok, request} <- Jason.decode(body),
         {:ok, answer} <- run(scope, fleet_id, request) do
      conn |> put_resp_content_type("application/json") |> send_resp(:ok, Jason.encode!(answer))
    else
      {:pass, false} -> send_resp(conn, :unauthorized, "")
      {:more, _part, conn} -> send_resp(conn, :request_entity_too_large, "")
      _malformed -> send_resp(conn, :bad_request, "")
    end
  end

  def call(conn, _opts), do: send_resp(conn, :not_found, "")

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _absent_or_more -> ""
    end
  end

  defp run(scope, fleet_id, %{"op" => op, "body" => body, "authority" => authority} = request)
       when scope in ~w(write check) and map_size(request) == 3 and is_map(body) do
    with true <- op in Writer.write_ops(),
         {:ok, authority} <- Authority.parse(authority) do
      reply =
        case scope do
          "write" -> Writer.command(fleet_id, op, body, authority)
          "check" -> Writer.check(fleet_id, op, body, authority)
        end

      {:ok, answer(reply)}
    end
  end

  defp run("await", fleet_id, %{"run_id" => run_id, "seq" => seq} = request)
       when map_size(request) == 2 and is_binary(run_id) and is_integer(seq) and seq >= 0,
       do: {:ok, %{"watermark" => Projector.await(fleet_id, run_id, seq)}}

  defp run(_scope, _fleet_id, _request), do: :error

  defp answer({:ok, reply}), do: %{"answer" => "ok", "reply" => reply}
  defp answer({:error, :unavailable}), do: %{"answer" => "unavailable"}
  defp answer({:error, :indeterminate}), do: %{"answer" => "indeterminate"}

  defp answer({:error, %NotKeyHolderError{token_id: token_id}}),
    do: %{"answer" => "not_key_holder", "token_id" => token_id}

  defp answer({:error, %EditsRestrictedError{token_id: token_id}}),
    do: %{"answer" => "edits_restricted", "token_id" => token_id}

  defp answer({:error, %OwnershipRefreshingError{}}), do: %{"answer" => "ownership_refreshing"}
  defp answer({:error, %{} = refusal}), do: %{"answer" => "refused", "refusal" => refusal}
end
