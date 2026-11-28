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

  alias Regents.Techtree.{Factory, ModelClimb, Network, Projects}
  alias Regents.Techtree.Factory.Order
  alias Regents.Techtree.Network.{Document, Error, Ingest, Key}

  alias RegentsWeb.Techtree.{
    AccountOrdersController,
    AgentAccountController,
    Outage,
    ProjectPackageController
  }

  alias RegentsWeb.Techtree.AgentTools.Public.Refused

  @max_mcp_package_bytes 350_000

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

    action :account_project_package, :map do
      description "Download a delivered Techtree project's gzipped tar package archive (base64-encoded when within the 512 KiB MCP budget, otherwise returns metadata and signed HTTP download URL)."

      argument :id, :string, allow_nil?: false, constraints: [min_length: 36, max_length: 36]

      run fn %{arguments: %{id: id}}, context ->
        with {:ok, uuid} <- Ecto.UUID.cast(id),
             {:ok, %{} = project} <-
               Outage.read(fn ->
                 ProjectPackageController.read_package(uuid, actor: context.actor)
               end) do
          bytes = project.package
          size = byte_size(bytes)

          url =
            RegentsWeb.Endpoint.url() <> "/api/v1/techtree/account/projects/#{project.id}/package"

          base = %{
            id: project.id,
            filename: ProjectPackageController.file_name(project),
            content_type: "application/gzip",
            size_bytes: size,
            sha256: project.package_sha256,
            download_url: url
          }

          if size <= @max_mcp_package_bytes do
            {:ok, Map.put(base, :package_base64, Base.encode64(bytes))}
          else
            {:ok,
             Map.merge(base, %{
               inline_omitted: true,
               hint:
                 "Archive exceeds inline MCP size (#{size} bytes). Download via signed HTTP GET #{url} or `regents techtree account project-package #{project.id}`."
             })}
          end
        else
          :database_down ->
            unavailable()

          _missing ->
            refused(
              "project_not_found",
              "Your person has no project package with that id.",
              "Call techtree_account_projects to list delivered projects."
            )
        end
      end
    end

    action :publication_submit, :map do
      description "Submit an independently signed Techtree Result proof bundle or withdrawal request as exact raw JSON text."

      argument :raw_body, :string, allow_nil?: false, constraints: [min_length: 2, trim?: false]
      argument :contributor_address, :string, allow_nil?: true
      argument :skill_name, :string, allow_nil?: true
      argument :skill_github_url, :string, allow_nil?: true

      run fn %{arguments: args}, context ->
        bytes = args.raw_body

        if byte_size(bytes) > Network.maximum_body_bytes() do
          refused(
            "submission_too_large",
            "Submission exceeds the maximum #{Network.maximum_body_bytes()} byte limit.",
            "Keep proof bundles within the documented size limit."
          )
        else
          submit_publication(bytes, args, context.actor)
        end
      end
    end

    action :model_climb_submit, :map do
      description "Verify and store a signed private Model Climb proof report for your paired person."

      argument :proof, :map, allow_nil?: false

      argument :idempotency_key, :string,
        allow_nil?: true,
        constraints: [min_length: 1, max_length: 255]

      run fn %{arguments: args}, context ->
        key =
          args[:idempotency_key] ||
            Map.get(args.proof, "report_digest") ||
            "sha256:" <>
              (:crypto.hash(:sha256, Jason.encode!(args.proof)) |> Base.encode16(case: :lower))

        case Outage.read(fn ->
               ModelClimb.submit_report(args.proof, key, actor: context.actor)
             end) do
          {:ok, {:ok, report}} ->
            {:ok,
             %{
               schema_version: "techtree.model-climb.operation.v1alpha1",
               operation_id: "model_climb_report_submit",
               report: report_summary(report),
               next_actions: [
                 %{
                   operation_id: "model_climb_report",
                   path: "/api/v1/techtree/model-climb/reports/#{report.report_digest}"
                 }
               ]
             }}

          {:ok, {:error, error}} ->
            refuse_model_climb_submit(error)

          :database_down ->
            unavailable()
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
      description "Request a new Techtree Uplift Factory order in one of the four lanes (skills, evals, environments, models). Note: /mcp caps total JSON payloads at 512 KiB (~370 KiB raw archive); for larger <= 5 MiB intake archives use POST /api/v1/techtree/account/orders or `regents techtree orders create`."

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
        with {:ok, lane} <- parse_lane(args.lane),
             {:ok, runbook} <- AccountOrdersController.parse_runbook(args[:runbook]) do
          input =
            %{lane: lane, title: args.title, success: args.success}
            |> maybe_put(:project_name, args[:project_name])
            |> maybe_put(:customer_company, args[:customer_company])
            |> maybe_put(:customer_contact_name, args[:customer_contact_name])
            |> maybe_put(:customer_contact_email, args[:customer_contact_email])
            |> maybe_put(:runbook, runbook)
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
        else
          {:error, code, message, hint} ->
            refused(code, message, hint)
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

  defp submit_publication(bytes, args, actor) do
    origin = RegentsWeb.Endpoint.url()

    case Document.kind(bytes) do
      {:ok, :submission} ->
        submit_proof_bundle(bytes, args, actor, origin)

      {:ok, :withdrawal} ->
        submit_withdrawal(bytes, actor, origin)

      {:error, %Error{} = error} ->
        refused(
          error.code,
          error.message,
          "Send exact signed JSON proof bundle or withdrawal bytes; see /techtree/docs/publish."
        )
    end
  end

  defp submit_proof_bundle(bytes, args, actor, origin) do
    options = [
      actor: actor,
      contributor_address: args[:contributor_address],
      skill_name: args[:skill_name],
      skill_github_url: args[:skill_github_url],
      origin: origin
    ]

    accepted =
      case Key.load() do
        {:ok, key} -> Ingest.accept(bytes, key, options)
        :error -> Ingest.recall(bytes, options)
      end

    case accepted do
      {:ok, entry, _outcome} ->
        {:ok, Jason.decode!(entry.receipt_bytes)}

      :unrecorded ->
        refused(
          "network_key_unavailable",
          "This site cannot countersign a receipt right now; nothing was recorded.",
          "Send the same document again later."
        )

      {:error, %Error{} = error} ->
        refused(
          error.code,
          error.message,
          "Fix what the message names and resubmit; see /techtree/docs/publish."
        )
    end
  end

  defp submit_withdrawal(bytes, actor, origin) do
    withdrawn =
      case Key.load() do
        {:ok, key} -> Ingest.withdraw(bytes, key, origin, actor: actor)
        :error -> Ingest.recall_withdrawal(bytes, actor: actor)
      end

    case withdrawn do
      {:ok, entry, _outcome} ->
        {:ok, Jason.decode!(entry.withdrawal_receipt_bytes)}

      :unrecorded ->
        refused(
          "network_key_unavailable",
          "This site cannot countersign a withdrawal receipt right now; nothing was recorded.",
          "Send the same document again later."
        )

      {:error, %Error{} = error} ->
        refused(
          error.code,
          error.message,
          "Fix what the message names and resubmit; see /techtree/docs/publish."
        )
    end
  end

  defp refuse_model_climb_submit(error) do
    case Ash.Error.to_error_class(error) do
      %Ash.Error.Invalid{errors: errors} ->
        case Enum.find(errors, &(Map.get(&1, :field) in [:proof, :idempotency_key])) do
          %{field: :idempotency_key} ->
            refused(
              "idempotency_conflict",
              "This idempotency_key was already used for a different proof.",
              "Send this proof with its own key; resend the first proof with its original key."
            )

          %{field: :proof, message: message} ->
            refused(
              "validation_error",
              message,
              "`regents techtree proof verify` runs every check locally; fix the failing check and resubmit."
            )

          _other ->
            refused(
              "validation_error",
              "The proof could not be read.",
              "Send the proof document as proof."
            )
        end

      _other ->
        unavailable()
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

  defp parse_lane(raw) do
    case Map.get(@lanes, to_string(raw || "")) do
      nil ->
        {:error, "invalid_lane", "lane must be one of skills, evals, environments, or models.",
         "Pass lane: \"skills\" | \"evals\" | \"environments\" | \"models\"."}

      lane ->
        {:ok, lane}
    end
  end

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
