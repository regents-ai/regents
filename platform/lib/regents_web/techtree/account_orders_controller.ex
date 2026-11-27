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
    with {:ok, lane} <- parse_lane(params["lane"] || params["kind"]),
         {:ok, runbook} <- parse_runbook(params["runbook"]) do
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
        |> maybe_put(:runbook, runbook)

      {:ok, input}
    end
  end

  defp parse_lane(raw) do
    case Map.get(@lanes, to_string(raw || "")) do
      nil ->
        {:error, :invalid_lane, "lane must be one of skills, evals, environments, or models.",
         "Pass lane: \"skills\" | \"evals\" | \"environments\" | \"models\"."}

      lane ->
        {:ok, lane}
    end
  end

  @runbook_keys ~w(mode auto_deliver max_gpu_cents default_gpu default_learning_rate default_training_mode)

  @doc false
  @spec parse_runbook(term()) ::
          {:ok, map() | nil} | {:error, :invalid_runbook, String.t(), String.t()}
  def parse_runbook(nil), do: {:ok, nil}

  def parse_runbook(raw) when is_map(raw) do
    unknown = Map.keys(raw) |> Enum.map(&to_string/1) |> Enum.reject(&(&1 in @runbook_keys))

    with [] <- unknown,
         {:ok, mode} <- parse_runbook_atom(raw, "mode", ~w(supervised auto)),
         {:ok, auto_deliver} <- parse_runbook_bool(raw, "auto_deliver"),
         {:ok, max_gpu_cents} <- parse_runbook_int(raw, "max_gpu_cents", 0, 1_000_000),
         {:ok, default_gpu} <- parse_runbook_atom(raw, "default_gpu", ~w(auto L4 G4 A100 H100)),
         {:ok, lr} <- parse_runbook_lr(raw, "default_learning_rate"),
         {:ok, train_mode} <- parse_runbook_atom(raw, "default_training_mode", ~w(sft rl)) do
      parsed =
        %{}
        |> maybe_put(:mode, mode)
        |> maybe_put(:auto_deliver, auto_deliver)
        |> maybe_put(:max_gpu_cents, max_gpu_cents)
        |> maybe_put(:default_gpu, default_gpu)
        |> maybe_put(:default_learning_rate, lr)
        |> maybe_put(:default_training_mode, train_mode)

      {:ok, parsed}
    else
      unknown when is_list(unknown) ->
        runbook_error("Unsupported runbook field(s): #{Enum.join(Enum.sort(unknown), ", ")}.")

      {:error, reason} ->
        runbook_error(reason)
    end
  end

  def parse_runbook(_other), do: runbook_error("runbook must be a JSON object.")

  defp parse_runbook_atom(raw, key, allowed) do
    case Map.fetch(raw, key) do
      :error ->
        {:ok, nil}

      {:ok, nil} ->
        {:ok, nil}

      {:ok, val} when is_binary(val) ->
        if val in allowed,
          do: {:ok, String.to_existing_atom(val)},
          else: {:error, "runbook.#{key} must be one of: #{Enum.join(allowed, ", ")}."}

      {:ok, _other} ->
        {:error, "runbook.#{key} must be one of: #{Enum.join(allowed, ", ")}."}
    end
  end

  defp parse_runbook_bool(raw, key) do
    case Map.fetch(raw, key) do
      :error -> {:ok, nil}
      {:ok, nil} -> {:ok, nil}
      {:ok, val} when is_boolean(val) -> {:ok, val}
      {:ok, _other} -> {:error, "runbook.#{key} must be a boolean."}
    end
  end

  defp parse_runbook_int(raw, key, min_v, max_v) do
    case Map.fetch(raw, key) do
      :error ->
        {:ok, nil}

      {:ok, nil} ->
        {:ok, nil}

      {:ok, val} when is_integer(val) and val >= min_v and val <= max_v ->
        {:ok, val}

      {:ok, _other} ->
        {:error, "runbook.#{key} must be an integer between #{min_v} and #{max_v}."}
    end
  end

  defp parse_runbook_lr(raw, key) do
    case Map.fetch(raw, key) do
      :error -> {:ok, nil}
      {:ok, nil} -> {:ok, nil}
      {:ok, val} when is_number(val) and val > 0 and val <= 1 -> {:ok, val * 1.0}
      {:ok, _other} -> {:error, "runbook.#{key} must be a number in (0, 1]."}
    end
  end

  defp runbook_error(message) do
    {:error, :invalid_runbook, message,
     "Allowed runbook fields: mode (supervised|auto), auto_deliver (boolean), max_gpu_cents (0..1000000), default_gpu (auto|L4|G4|A100|H100), default_learning_rate ((0,1]), default_training_mode (sft|rl)."}
  end

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
