defmodule RegentsWeb.Techtree.FactoryOrdersController do
  @moduledoc """
  Operator-authenticated HTTP bridge endpoints for `uplift-factory`'s
  `UpliftFactory.Factory.OrderBridge`:

  - `GET  /api/v1/techtree/factory/orders?state=paid`
  - `POST /api/v1/techtree/factory/orders/:id/claim`
  - `POST /api/v1/techtree/factory/orders/:id/deliver`

  Authenticated via constant-time `Authorization: Bearer <token>` comparison
  against `config :regents, :techtree_factory_operator_token`. Stays completely
  closed (`503`) when no operator token is configured.
  """

  use RegentsWeb, :controller

  alias Regents.Account.Actors.System, as: SystemActor
  alias Regents.Techtree.{Factory, Projects}
  alias Regents.Techtree.Factory.{Order, Runbook}
  alias Regents.Techtree.Projects.Package
  alias RegentsWeb.Techtree.{ExactResponse, Outage}

  plug :authorize_operator

  @allowed_states ~w(requested checking quoted paid running awaiting_decision delivered failed refused expired cancelled)
  @email_pattern ~r/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  @sha256_pattern ~r/\A[0-9a-f]{64}\z/

  def index(conn, params) do
    raw_state = Map.get(params, "state", "paid")

    with {:ok, state_atom} <- parse_state(raw_state),
         {:ok, orders} <-
           Outage.read(fn ->
             Factory.list_bridge_orders!(%{state: state_atom}, actor: %SystemActor{})
           end) do
      private_json(conn, %{"orders" => Enum.map(orders, &bridge_order/1)})
    else
      {:error, :invalid_state} ->
        ExactResponse.send_error(
          conn,
          400,
          :invalid_state,
          "Unsupported order state filter.",
          "Use one of: #{Enum.join(@allowed_states, ", ")}."
        )

      :database_down ->
        unavailable(conn)
    end
  end

  # Serves raw `.tar.gz` bytes as `application/octet-stream` so HTTP clients
  # such as Elixir Req never auto-decompress the archive before tar extraction.
  # sobelow_skip ["XSS.SendResp"]
  def claim(conn, %{"id" => id}) do
    with {:ok, uuid} <- cast_uuid(id),
         {:ok, order} <- fetch_order(uuid),
         :ok <- require_claimable(order),
         {:ok, claimed} <- do_claim(order) do
      conn
      |> put_resp_content_type("application/octet-stream", nil)
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("x-material-sha256", claimed.material_sha256 || "")
      |> send_resp(200, claimed.material_archive)
    else
      :not_found ->
        order_not_found(conn)

      {:conflict, message} ->
        ExactResponse.send_error(
          conn,
          409,
          :order_not_claimable,
          message,
          "Only paid orders with uploaded materials can be claimed."
        )

      {:unprocessable, message} ->
        ExactResponse.send_error(
          conn,
          422,
          :materials_missing,
          message,
          "Attach a valid <= 5 MiB .tar.gz material archive before claiming."
        )

      :database_down ->
        unavailable(conn)
    end
  end

  def deliver(conn, %{"id" => id} = params) do
    with {:ok, uuid} <- cast_uuid(id),
         {:ok, payload} <- parse_delivery_payload(params),
         {:ok, order} <- fetch_order(uuid) do
      deliver_or_idempotent(conn, order, payload)
    else
      :not_found ->
        order_not_found(conn)

      {:unprocessable, code, message, hint} ->
        ExactResponse.send_error(conn, 422, code, message, hint)

      :database_down ->
        unavailable(conn)
    end
  end

  defp deliver_or_idempotent(
         conn,
         %{state: :delivered, delivered_project_id: project_id, external_job_id: existing_job} =
           order,
         %{job_id: job_id, sha256: sha256}
       )
       when is_binary(project_id) do
    case Outage.read(fn -> Projects.get_project_for_system(project_id, actor: %SystemActor{}) end) do
      {:ok, {:ok, %{package_sha256: ^sha256} = project}}
      when is_nil(existing_job) or existing_job == job_id ->
        private_json(conn, %{
          order_id: order.id,
          project_id: project.id,
          sha256: sha256,
          status: "delivered",
          idempotent: true
        })

      {:ok, _other} ->
        ExactResponse.send_error(
          conn,
          409,
          :already_delivered,
          "This order was already delivered with a different package digest.",
          "Inspect the existing delivered project before retrying."
        )

      :database_down ->
        unavailable(conn)
    end
  end

  defp deliver_or_idempotent(conn, %{state: state}, _payload)
       when state not in [:paid, :running, :awaiting_decision] do
    ExactResponse.send_error(
      conn,
      409,
      :order_not_deliverable,
      "Order is in state #{state} and cannot accept a delivery.",
      "Only paid, running, or awaiting_decision orders accept deliveries."
    )
  end

  defp deliver_or_idempotent(conn, order, %{
         job_id: job_id,
         sha256: sha256,
         bytes: bytes
       }) do
    case Outage.read(fn ->
           Factory.deliver_order(
             order,
             %{package_bytes: bytes, expected_sha256: sha256, external_job_id: job_id},
             actor: %SystemActor{}
           )
         end) do
      {:ok, {:ok, delivered}} ->
        private_json(conn, %{
          order_id: delivered.id,
          project_id: delivered.delivered_project_id,
          sha256: sha256,
          status: "delivered",
          idempotent: false
        })

      {:ok, {:error, error}} ->
        ExactResponse.send_error(
          conn,
          422,
          :invalid_package,
          validation_message(error, "Package failed uplift-package validation."),
          "Ensure the archive is a valid uplift-package/1 or uplift-package/2 tarball matching sha256."
        )

      :database_down ->
        unavailable(conn)
    end
  end

  defp fetch_order(uuid) do
    case Outage.read(fn -> Factory.get_bridge_order(uuid, actor: %SystemActor{}) end) do
      {:ok, {:ok, %Order{} = order}} -> {:ok, order}
      {:ok, {:ok, nil}} -> :not_found
      {:ok, {:error, _reason}} -> :not_found
      :database_down -> :database_down
    end
  end

  defp require_claimable(%{state: state}) when state != :paid,
    do: {:conflict, "Order is in state #{state} and cannot be claimed."}

  defp require_claimable(%{material_sha256: nil}),
    do: {:unprocessable, "Order has no uploaded material archive."}

  defp require_claimable(_order), do: :ok

  defp do_claim(order) do
    case Outage.read(fn -> claim_and_load_materials(order) end) do
      {:ok, {:ok, %{material_archive: bytes} = claimed}} when is_binary(bytes) ->
        {:ok, claimed}

      {:ok, {:ok, _empty}} ->
        {:unprocessable, "Order material archive bytes are missing."}

      {:ok, {:error, _error}} ->
        {:conflict, "Order could not be claimed; it may already have been claimed."}

      :database_down ->
        :database_down
    end
  end

  defp claim_and_load_materials(order) do
    actor = %SystemActor{}

    with {:ok, _claimed} <- Factory.claim_order(order, actor: actor) do
      Factory.get_bridge_materials(order.id, actor: actor)
    end
  end

  defp parse_delivery_payload(%{
         "job_id" => job_id,
         "sha256" => sha256,
         "size_bytes" => size_bytes,
         "archive_base64" => encoded
       })
       when is_binary(job_id) and job_id != "" and is_binary(sha256) and
              is_integer(size_bytes) and size_bytes > 0 and is_binary(encoded) do
    with true <- Regex.match?(@sha256_pattern, sha256),
         {:ok, bytes} <- Base.decode64(encoded),
         true <- byte_size(bytes) == size_bytes,
         true <- Package.sha256(bytes) == sha256 do
      {:ok, %{job_id: job_id, sha256: sha256, bytes: bytes}}
    else
      false ->
        {:unprocessable, :digest_mismatch,
         "Declared sha256 or size_bytes does not match the decoded archive.",
         "Recompute sha256 and size_bytes over the raw .tar.gz bytes before encoding."}

      :error ->
        {:unprocessable, :invalid_base64, "archive_base64 is not valid base64.",
         "Encode the raw .tar.gz bytes with standard base64."}
    end
  end

  defp parse_delivery_payload(_params) do
    {:unprocessable, :invalid_delivery_payload,
     "Delivery requires job_id, sha256, size_bytes, and archive_base64.",
     "Send JSON with job_id, sha256 (64 hex), positive size_bytes, and archive_base64."}
  end

  defp bridge_order(order) do
    %{
      "id" => order.id,
      "project_name" => order.project_name || fallback_project_name(order),
      "kind" => Order.bridge_kind(order.lane),
      "title" => order.title,
      "customer" => %{
        "company" => non_empty(order.customer_company, "Techtree Customer"),
        "contact_name" =>
          non_empty(order.customer_contact_name, order.agent_wallet || "Techtree Customer"),
        "contact_email" => valid_email(order.customer_contact_email),
        "account_id" => nil
      },
      "quote_cents" => Order.quote_cents(order.quote_amount),
      "runbook" => Runbook.to_bridge_map(order.runbook)
    }
  end

  defp fallback_project_name(order) do
    "order-" <> binary_part(order.id, 0, 8)
  end

  defp non_empty(value, fallback) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed, else: fallback
  end

  defp non_empty(_value, fallback), do: fallback

  defp valid_email(value) when is_binary(value) do
    trimmed = String.trim(value)
    if Regex.match?(@email_pattern, trimmed), do: trimmed, else: "orders@regents.sh"
  end

  defp valid_email(_other), do: "orders@regents.sh"

  defp parse_state(state) when state in @allowed_states, do: {:ok, String.to_existing_atom(state)}
  defp parse_state(_other), do: {:error, :invalid_state}

  defp cast_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :not_found
    end
  end

  defp authorize_operator(conn, _opts) do
    with expected when is_binary(expected) <- configured_token(),
         provided when is_binary(provided) <- bearer_token(conn),
         true <- Plug.Crypto.secure_compare(provided, expected) do
      conn
    else
      nil ->
        unconfigured_or_unauthorized(conn, configured_token())

      false ->
        unauthorized(conn)
    end
  end

  defp unconfigured_or_unauthorized(conn, nil) do
    conn
    |> ExactResponse.send_error(
      503,
      :factory_bridge_not_configured,
      "The Uplift Factory operator bridge is not configured on this host.",
      "Configure TECHTREE_FACTORY_OPERATOR_TOKEN or TECHTREE_FACTORY_OPERATOR_TOKEN_FILE."
    )
    |> halt()
  end

  defp unconfigured_or_unauthorized(conn, _configured), do: unauthorized(conn)

  defp configured_token do
    case Application.get_env(:regents, :techtree_factory_operator_token) do
      token when is_binary(token) and byte_size(token) > 0 -> token
      _other -> nil
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _other -> nil
    end
  end

  defp unauthorized(conn) do
    conn
    |> ExactResponse.send_error(
      401,
      :unauthorized,
      "Valid operator Bearer authentication is required.",
      "Send Authorization: Bearer <operator_token>."
    )
    |> halt()
  end

  defp order_not_found(conn) do
    ExactResponse.send_error(
      conn,
      404,
      :order_not_found,
      "No factory order has that id.",
      "List orders at GET /api/v1/techtree/factory/orders?state=paid."
    )
  end

  defp private_json(conn, body),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(body)

  defp unavailable(conn) do
    ExactResponse.send_error(
      conn,
      503,
      :unavailable,
      "Factory orders could not be reached right now.",
      "Try again in a moment."
    )
  end

  defp validation_message(%{errors: errors}, fallback) when is_list(errors) do
    errors
    |> Enum.flat_map(fn
      %{errors: nested} when is_list(nested) ->
        [validation_message(%{errors: nested}, "")]

      %{field: field, message: msg} when not is_nil(field) and is_binary(msg) ->
        ["#{field}: #{msg}"]

      %{message: msg} when is_binary(msg) ->
        [msg]

      _other ->
        []
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> case do
      [] -> fallback
      messages -> Enum.join(messages, "; ")
    end
  end

  defp validation_message(_error, fallback), do: fallback
end
