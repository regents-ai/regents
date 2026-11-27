defmodule RegentsWeb.Techtree.AgentTools.Account do
  @moduledoc """
  Paired-agent hosted MCP tool actions for Techtree at `/mcp`: reading delivered
  projects, private Model Climb proof reports, and creating/listing/reading/
  cancelling Uplift Factory orders.

  Every action is gated by `{RegentAgents.Checks.Paired, repo: Regents.Repo}`
  and delegates strictly to Ash domain code interfaces (`Projects`, `ModelClimb`,
  `Factory`), returning uniform `%{error: %{code, message, hint}}` refusals.
  """

  use Ash.Resource,
    domain: RegentsWeb.Techtree.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Techtree.{Factory, ModelClimb, Projects}
  alias Regents.Techtree.Factory.Order
  alias RegentsWeb.Techtree.{AccountOrdersController, AgentAccountController, Outage}
  alias RegentsWeb.Techtree.AgentTools.Public.Refused

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

  actions do
    action :account_projects, :map do
      description "List delivered Techtree projects belonging to your paired person, newest first."

      run fn _input, context ->
        case Outage.read(fn -> Projects.list_my_projects!(actor: context.actor) end) do
          {:ok, projects} ->
            {:ok, %{projects: Enum.map(projects, &AgentAccountController.listed/1)}}

          :database_down ->
            unavailable()
        end
      end
    end

    action :account_project, :map do
      description "Read one delivered Techtree project with its structured manifest, rerun_test receipt, report, and package metadata."

      argument :id, :string, allow_nil?: false, constraints: [min_length: 36, max_length: 36]

      run fn %{arguments: %{id: id}}, context ->
        with {:ok, uuid} <- Ecto.UUID.cast(id),
             {:ok, %{} = project} <-
               Outage.read(fn -> Projects.get_my_project!(uuid, actor: context.actor) end) do
          {:ok, AgentAccountController.whole(project)}
        else
          :database_down ->
            unavailable()

          _missing ->
            refused(
              "project_not_found",
              "Your person has no project with that id.",
              "Call techtree_account_projects to list delivered projects."
            )
        end
      end
    end

    action :model_climb_list, :map do
      description "List private Model Climb proof reports stored for your paired person, newest first."

      run fn _input, context ->
        case Outage.read(fn -> ModelClimb.list_my_reports!(actor: context.actor) end) do
          {:ok, reports} ->
            {:ok, %{reports: Enum.map(reports, &report_summary/1)}}

          :database_down ->
            unavailable()
        end
      end
    end

    action :model_climb_show, :map do
      description "Read one private Model Climb proof report by digest for your paired person."

      argument :digest, :string, allow_nil?: false, constraints: [min_length: 10, max_length: 120]

      run fn %{arguments: %{digest: digest}}, context ->
        case Outage.read(fn -> ModelClimb.get_my_report(digest, actor: context.actor) end) do
          {:ok, {:ok, %{} = report}} ->
            {:ok,
             %{
               report:
                 report
                 |> report_summary()
                 |> Map.put(:proof, Jason.decode!(report.proof))
             }}

          {:ok, _missing} ->
            refused(
              "not_found",
              "No Model Climb report with that digest belongs to your paired person.",
              "Call techtree_model_climb_list to list available report digests."
            )

          :database_down ->
            unavailable()
        end
      end
    end

    action :orders_list, :map do
      description "List Techtree Uplift Factory orders belonging to your paired person, newest first."

      run fn _input, context ->
        case Outage.read(fn -> Factory.list_my_orders!(actor: context.actor) end) do
          {:ok, orders} ->
            {:ok, %{orders: Enum.map(orders, &AccountOrdersController.serialize_order/1)}}

          :database_down ->
            unavailable()
        end
      end
    end

    action :orders_show, :map do
      description "Read one Techtree Uplift Factory order's state, quote, runbook, materials digest, and delivered project link."

      argument :id, :string, allow_nil?: false, constraints: [min_length: 36, max_length: 36]

      run fn %{arguments: %{id: id}}, context ->
        with {:ok, uuid} <- Ecto.UUID.cast(id),
             {:ok, %Order{} = order} <-
               Outage.read(fn -> Factory.get_my_order!(uuid, actor: context.actor) end) do
          {:ok, AccountOrdersController.serialize_order(order)}
        else
          :database_down ->
            unavailable()

          _missing ->
            refused(
              "order_not_found",
              "Your person has no Techtree order with that id.",
              "Call techtree_orders_list to list your orders."
            )
        end
      end
    end

    action :orders_create, :map do
      description "Request a new Techtree Uplift Factory order in one of the four lanes (skills, evals, environments, models)."

      argument :lane, :string, allow_nil?: false
      argument :title, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 200]

      argument :success, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 2000]

      argument :project_name, :string, allow_nil?: true, constraints: [max_length: 63]
      argument :customer_company, :string, allow_nil?: true, constraints: [max_length: 200]
      argument :customer_contact_name, :string, allow_nil?: true, constraints: [max_length: 200]
      argument :customer_contact_email, :string, allow_nil?: true, constraints: [max_length: 320]
      argument :runbook, :map, allow_nil?: true
      argument :material_archive_base64, :string, allow_nil?: true

      run fn %{arguments: args}, context ->
        case Map.get(@lanes, args.lane) do
          nil ->
            refused(
              "invalid_lane",
              "lane must be one of skills, evals, environments, or models.",
              "Pass lane: \"skills\" | \"evals\" | \"environments\" | \"models\"."
            )

          lane ->
            input =
              %{lane: lane, title: args.title, success: args.success}
              |> maybe_put(:project_name, args[:project_name])
              |> maybe_put(:customer_company, args[:customer_company])
              |> maybe_put(:customer_contact_name, args[:customer_contact_name])
              |> maybe_put(:customer_contact_email, args[:customer_contact_email])
              |> maybe_put(:runbook, parse_runbook(args[:runbook]))
              |> maybe_put(:material_archive_base64, args[:material_archive_base64])

            case Outage.read(fn -> Factory.request_order(input, actor: context.actor) end) do
              {:ok, {:ok, order}} ->
                {:ok, AccountOrdersController.serialize_order(order)}

              {:ok, {:error, error}} ->
                refused(
                  "order_invalid",
                  AccountOrdersController.validation_message(
                    error,
                    "Order fields or materials failed validation."
                  ),
                  "Check lane, title, success, runbook, and material_archive_base64."
                )

              :database_down ->
                unavailable()
            end
        end
      end
    end

    action :orders_cancel, :map do
      description "Cancel an unpaid Techtree Uplift Factory order (requested, checking, or quoted)."

      argument :id, :string, allow_nil?: false, constraints: [min_length: 36, max_length: 36]

      run fn %{arguments: %{id: id}}, context ->
        with {:ok, uuid} <- Ecto.UUID.cast(id),
             {:ok, %Order{} = order} <-
               Outage.read(fn -> Factory.get_my_order!(uuid, actor: context.actor) end),
             {:ok, result} <-
               Outage.read(fn -> Factory.cancel_order(order, actor: context.actor) end) do
          case result do
            {:ok, cancelled} ->
              {:ok, AccountOrdersController.serialize_order(cancelled)}

            {:error, _error} ->
              refused(
                "order_not_cancellable",
                "Order is in state #{order.state} and cannot be cancelled.",
                "Only requested, checking, or quoted orders can be cancelled."
              )
          end
        else
          :database_down ->
            unavailable()

          _missing ->
            refused(
              "order_not_found",
              "Your person has no Techtree order with that id.",
              "Call techtree_orders_list to list your orders."
            )
        end
      end
    end
  end

  policies do
    policy always() do
      forbid_unless {RegentAgents.Checks.Paired, repo: Regents.Repo}
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  defp report_summary(report) do
    %{
      report_digest: report.report_digest,
      signer_key_id: report.signer_key_id,
      results: report.results,
      paired_outcomes: report.paired_outcomes,
      received_at: report.inserted_at
    }
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

  defp unavailable do
    refused("unavailable", "Techtree account data is unavailable.", "Try again in a moment.")
  end

  defp refused(code, message, hint) do
    body = %{error: %{code: to_string(code), message: message, hint: hint}}
    {:error, Refused.exception(body: body)}
  end
end
