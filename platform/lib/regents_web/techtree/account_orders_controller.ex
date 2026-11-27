defmodule RegentsWeb.Techtree.AccountOrdersController do
  @moduledoc """
  Paired-agent SIWA endpoints for creating, listing, reading, and cancelling
  Techtree Uplift Factory orders belonging to the paired person:

  - `GET  /api/v1/techtree/account/orders`
  - `POST /api/v1/techtree/account/orders`
  - `GET  /api/v1/techtree/account/orders/:id`
  - `POST /api/v1/techtree/account/orders/:id/cancel`
  """

  use RegentsWeb, :controller

  alias Regents.Techtree.Factory
  alias Regents.Techtree.Factory.{Order, Runbook}
  alias RegentsWeb.Techtree.{ExactResponse, Outage}

  @lanes %{
    "skills" => :skills,
    "skill" => :skills,
    "evals" => :evals,
    "eval" => :evals,
    "environments" => :environments,
    "environment" => :environments,
    "models" => :models,
    "model" => :models
  }

  def index(conn, _params) do
    case Outage.read(fn -> Factory.list_my_orders!(actor: conn.assigns.actor) end) do
      {:ok, orders} ->
        private_json(conn, %{orders: Enum.map(orders, &serialize_order/1)})

      :database_down ->
        unavailable(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, uuid} <- cast_uuid(id),
         {:ok, %Order{} = order} <-
           Outage.read(fn -> Factory.get_my_order!(uuid, actor: conn.assigns.actor) end) do
      private_json(conn, serialize_order(order))
    else
      :database_down -> unavailable(conn)
      _missing -> order_not_found(conn)
    end
  end

  def create(conn, params) do
    with {:ok, input} <- build_request_input(params),
         {:ok, result} <-
           Outage.read(fn -> Factory.request_order(input, actor: conn.assigns.actor) end) do
      case result do
        {:ok, order} ->
          conn
          |> put_resp_header("cache-control", "no-store")
          |> put_status(201)
          |> json(serialize_order(order))

        {:error, error} ->
          ExactResponse.send_error(
            conn,
            422,
            :order_invalid,
            validation_message(error, "Order fields or materials failed validation."),
            "Check lane (skills|evals|environments|models), title, success, runbook, and material_archive_base64 (<= 5 MiB .tar.gz)."
          )
      end
    else
      {:error, code, message, hint} ->
        ExactResponse.send_error(conn, 422, code, message, hint)

      :database_down ->
        unavailable(conn)
    end
  end

  def cancel(conn, %{"id" => id}) do
    with {:ok, uuid} <- cast_uuid(id),
         {:ok, %Order{} = order} <-
           Outage.read(fn -> Factory.get_my_order!(uuid, actor: conn.assigns.actor) end),
         {:ok, result} <-
           Outage.read(fn -> Factory.cancel_order(order, actor: conn.assigns.actor) end) do
      case result do
        {:ok, cancelled} ->
          private_json(conn, serialize_order(cancelled))

        {:error, _error} ->
          ExactResponse.send_error(
            conn,
            409,
            :order_not_cancellable,
            "Order is in state #{order.state} and can no longer be cancelled.",
            "Only requested, checking, or quoted orders can be cancelled."
          )
      end
    else
      :database_down -> unavailable(conn)
      _missing -> order_not_found(conn)
    end
  end

  @doc "Canonical JSON serialization of a customer/agent order."
  @spec serialize_order(Order.t()) :: map()
  def serialize_order(order) do
    %{
      id: order.id,
      lane: order.lane,
      kind: Order.bridge_kind(order.lane),
      title: order.title,
      success: order.success,
      project_name: order.project_name,
      state: order.state,
      quote:
        if order.quote_amount do
          %{
            amount_usdc_micro: order.quote_amount,
            cents: Order.quote_cents(order.quote_amount),
            scope: order.quote_scope,
            expires_at: order.quote_expires_at,
            payment_reference: order.payment_reference
          }
        end,
      runbook: Runbook.to_bridge_map(order.runbook),
      materials:
        if order.material_sha256 do
          %{
            sha256: order.material_sha256,
            size_bytes: order.material_size
          }
        end,
      requested_at: order.requested_at,
      quoted_at: order.quoted_at,
      paid_at: order.paid_at,
      claimed_at: order.claimed_at,
      delivered_at: order.delivered_at,
      cancelled_at: order.cancelled_at,
      delivered_project_id: order.delivered_project_id,
      delivered_project_url:
        if order.delivered_project_id do
          url(~p"/techtree/account/projects/#{order.delivered_project_id}")
        end,
      delivered_project_api_url:
        if order.delivered_project_id do
          url(~p"/api/v1/techtree/account/projects/#{order.delivered_project_id}")
        end
    }
  end

  defp build_request_input(params) when is_map(params) do
    case Map.get(@lanes, to_string(params["lane"] || params["kind"] || "")) do
      nil ->
        {:error, :invalid_lane, "lane must be one of skills, evals, environments, or models.",
         "Pass lane: \"skills\" | \"evals\" | \"environments\" | \"models\"."}

      lane ->
        input =
          %{
            lane: lane,
            title: params["title"],
            success: params["success"]
          }
          |> maybe_put(:project_name, params["project_name"])
          |> maybe_put(:customer_company, params["customer_company"])
          |> maybe_put(:customer_contact_name, params["customer_contact_name"])
          |> maybe_put(:customer_contact_email, params["customer_contact_email"])
          |> maybe_put(:material_archive_base64, params["material_archive_base64"])
          |> maybe_put(:runbook, parse_runbook(params["runbook"]))

        {:ok, input}
    end
  end

  defp parse_runbook(%{} = raw) do
    %{}
    |> maybe_put(:mode, parse_atom(raw["mode"], ~w(supervised auto)))
    |> maybe_put(:auto_deliver, if(is_boolean(raw["auto_deliver"]), do: raw["auto_deliver"]))
    |> maybe_put(:max_gpu_cents, raw["max_gpu_cents"])
    |> maybe_put(:default_gpu, parse_atom(raw["default_gpu"], ~w(auto L4 G4 A100 H100)))
    |> maybe_put(:default_learning_rate, raw["default_learning_rate"])
    |> maybe_put(:default_training_mode, parse_atom(raw["default_training_mode"], ~w(sft rl)))
  end

  defp parse_runbook(_other), do: nil

  defp parse_atom(val, allowed) when is_binary(val) do
    if val in allowed, do: String.to_existing_atom(val), else: nil
  end

  defp parse_atom(_val, _allowed), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp cast_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :not_found
    end
  end

  defp order_not_found(conn) do
    ExactResponse.send_error(
      conn,
      404,
      :order_not_found,
      "Your person has no Techtree order with that id.",
      "List orders at #{url(~p"/api/v1/techtree/account/orders")}."
    )
  end

  defp private_json(conn, answer),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(answer)

  defp unavailable(conn) do
    ExactResponse.send_error(
      conn,
      503,
      :unavailable,
      "That could not be reached right now.",
      "Try again in a moment."
    )
  end

  @doc false
  def validation_message(%{errors: errors}, fallback) when is_list(errors) do
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

  def validation_message(_error, fallback), do: fallback
end
