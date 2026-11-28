defmodule RegentsWeb.Techtree.AgentTools.Public do
  @moduledoc """
  Read-only hosted MCP tool actions for Techtree at `/mcp`. Every refusal
  follows Regents' shared `%{error: %{code, message, hint}}` envelope.
  """

  use Ash.Resource,
    domain: RegentsWeb.Techtree.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Techtree.Catalog.Digest
  alias Regents.Techtree.Catalog.Query, as: CatalogQuery
  alias Regents.Techtree.Network.{Projection, Query}
  alias Regents.Techtree.Train.Comparisons
  alias Regents.Techtree.WalletBench.Reading

  alias RegentsWeb.Techtree.{
    ClimbController,
    Outage,
    PublicDocuments,
    TrainController,
    WalletBenchEvidenceController,
    WalletBenchScores
  }

  defmodule Refused do
    @moduledoc false
    use Splode.Error, fields: [:body], class: :invalid

    def message(%{body: %{error: %{message: message}}}), do: message
  end

  actions do
    action :catalog, :map do
      description "Read the active Techtree catalog of published Climbs and Skills."

      run fn _input, _context ->
        case Outage.read(&CatalogQuery.catalog_bytes/0) do
          {:ok, {:ok, bytes, _digest}} ->
            {:ok, Jason.decode!(bytes)}

          {:ok, {:error, error}} ->
            refused(error.code, error.message, "Retry or check /api/v1/health.")

          :database_down ->
            refused("unavailable", "Techtree catalog is unavailable.", "Try again in a moment.")
        end
      end
    end

    action :bootstrap, :map do
      description "Read the active Techtree release's CLI bootstrap and install metadata."

      run fn _input, _context ->
        case Outage.read(&CatalogQuery.bootstrap_payload/0) do
          {:ok, {:ok, payload, _digest}} ->
            {:ok, Jason.decode!(payload)}

          {:ok, {:error, error}} ->
            refused(error.code, error.message, "Retry or check /api/v1/health.")

          :database_down ->
            refused(
              "unavailable",
              "Techtree bootstrap is unavailable.",
              "Try again in a moment."
            )
        end
      end
    end

    action :climb, :map do
      description "Read one published Techtree Climb by slug."

      argument :slug, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 120]

      run fn %{arguments: %{slug: slug}}, _context ->
        case Outage.read(fn -> CatalogQuery.get_climb_by_slug(slug) end) do
          {:ok, {:ok, entry}} ->
            {:ok, ClimbController.projection(entry)}

          {:ok, {:error, error}} ->
            refused(
              error.code,
              error.message,
              "Call techtree_catalog to list available Climb slugs."
            )

          :database_down ->
            refused("unavailable", "Techtree catalog is unavailable.", "Try again in a moment.")
        end
      end
    end

    action :publications, :map do
      description "List published Techtree evaluation Results, newest first, with optional limit, before_sequence, agent/agent_version, model, and challenge filters."

      argument :limit, :integer, default: 25, allow_nil?: false, constraints: [min: 1, max: 100]
      argument :before_sequence, :integer, allow_nil?: true, constraints: [min: 1]
      argument :agent, :string, allow_nil?: true, constraints: [min_length: 1, max_length: 128]

      argument :agent_version, :string,
        allow_nil?: true,
        constraints: [min_length: 1, max_length: 128]

      argument :model, :string, allow_nil?: true, constraints: [min_length: 1, max_length: 512]

      argument :challenge, :string,
        allow_nil?: true,
        constraints: [min_length: 1, max_length: 512]

      run fn %{arguments: args}, _context ->
        params =
          %{"limit" => Integer.to_string(args.limit)}
          |> maybe_put_before(args[:before_sequence])
          |> maybe_put_param("agent", args[:agent])
          |> maybe_put_param("agent_version", args[:agent_version])
          |> maybe_put_param("model", args[:model])
          |> maybe_put_param("challenge", args[:challenge])

        with {:ok, options} <- Query.read_page_options(params),
             {:ok, page} <- Outage.read(fn -> Query.page(options) end) do
          bytes = Projection.log(page, RegentsWeb.Endpoint.url())
          {:ok, Jason.decode!(bytes)}
        else
          {:error, message} ->
            refused(
              "publication_query_invalid",
              message,
              "Pass integer limit (1..100), optional before_sequence, model, challenge, or agent together with agent_version."
            )

          :database_down ->
            refused("unavailable", "Techtree results are unavailable.", "Try again in a moment.")
        end
      end
    end

    action :publication_show, :map do
      description "Read one published Techtree Result by bundle digest."

      argument :bundle_digest, :string,
        allow_nil?: false,
        constraints: [min_length: 10, max_length: 120]

      run fn %{arguments: %{bundle_digest: digest}}, _context ->
        if Digest.valid?(digest) do
          read_publication(digest)
        else
          refused(
            "publication_digest_invalid",
            "The bundle_digest is not a valid sha256 digest.",
            "Call techtree_publications to list valid bundle digests."
          )
        end
      end
    end

    action :publication_bundle, :map do
      description "Read the exact submitted JSON proof bundle for a published Techtree Result."

      argument :bundle_digest, :string,
        allow_nil?: false,
        constraints: [min_length: 10, max_length: 120]

      run fn %{arguments: %{bundle_digest: digest}}, _context ->
        if Digest.valid?(digest) do
          read_publication_bundle(digest)
        else
          refused(
            "publication_digest_invalid",
            "The bundle_digest is not a valid sha256 digest.",
            "Call techtree_publications to list valid bundle digests."
          )
        end
      end
    end

    action :skill, :map do
      description "Read a published Techtree Skill's files and standing Results by root digest."

      argument :root_digest, :string,
        allow_nil?: false,
        constraints: [min_length: 10, max_length: 120]

      run fn %{arguments: %{root_digest: digest}}, _context ->
        if Digest.valid?(digest) do
          read_skill(digest)
        else
          refused(
            "skill_digest_invalid",
            "The root_digest is not a valid sha256 digest.",
            "Use a skill root digest listed on a published Result from techtree_publications."
          )
        end
      end
    end

    action :wallet_bench, :map do
      description "Read the Agent Wallet Bench score grids."

      run fn _input, _context ->
        case Outage.read(&Reading.reading/0) do
          {:ok, reading} ->
            {:ok, WalletBenchScores.feed(reading)}

          :database_down ->
            refused(
              "scores_unavailable",
              "Wallet Bench is unavailable.",
              "Try again in a moment."
            )
        end
      end
    end

    action :train_comparisons, :map do
      description "List published public Skill comparison demonstrations."

      run fn _input, _context ->
        comparisons = Enum.map(Comparisons.list(), &TrainController.entry/1)
        {:ok, %{comparisons: comparisons}}
      end
    end

    action :train_report, :map do
      description "Read one published Techtree Train comparison's full per-case JSON report."

      argument :slug, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 120]

      run fn %{arguments: %{slug: slug}}, _context ->
        case Comparisons.download(slug) do
          {:ok, bytes, _digest} ->
            {:ok, Jason.decode!(bytes)}

          :error ->
            refused(
              "comparison_not_found",
              "No Train comparison has that slug.",
              "Call techtree_train_comparisons to list available comparison slugs."
            )
        end
      end
    end

    action :wallet_bench_show, :map do
      description "Read one Agent Wallet Bench attempt's summary, rulings, and checks by attempt UUID."

      argument :id, :string, allow_nil?: false, constraints: [min_length: 36, max_length: 36]

      run fn %{arguments: %{id: id}}, _context ->
        case WalletBenchEvidenceController.summary_data(id) do
          {:ok, payload} ->
            {:ok, payload}

          :database_down ->
            refused(
              "wallet_test_unavailable",
              "The wallet test can't be read right now; try again shortly.",
              "Retry in a moment."
            )

          :not_found ->
            refused(
              "wallet_test_not_found",
              "No wallet test has that id.",
              "Call techtree_wallet_bench to list attempt ids."
            )
        end
      end
    end

    action :docs_markdown, :map do
      description "Read Techtree's docs index as Markdown."

      run fn _input, _context ->
        case PublicDocuments.document("/techtree/docs") do
          %{title: title, markdown: markdown} ->
            {:ok, %{path: "/techtree/docs", title: title, markdown: markdown}}

          nil ->
            refused("not_found", "Techtree docs could not be read.", "Try again in a moment.")
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  defp read_publication(digest) do
    case Outage.read(fn -> fetch_entry_with_runs(digest) end) do
      {:ok, {:ok, entry, runs_behind}} ->
        bytes = Projection.entry(entry, runs_behind, RegentsWeb.Endpoint.url())
        {:ok, Jason.decode!(bytes)}

      {:ok, :error} ->
        refused(
          "publication_missing",
          "No published Result has that bundle digest.",
          "Call techtree_publications to list available bundle digests."
        )

      :database_down ->
        refused("unavailable", "Techtree results are unavailable.", "Try again in a moment.")
    end
  end

  defp read_publication_bundle(digest) do
    case Outage.read(fn -> Query.get_entry(digest) end) do
      {:ok, {:ok, entry}} ->
        if Query.withdrawn?(entry) do
          refused(
            "publication_withdrawn",
            "The participant withdrew this run, so this site no longer hands out the submitted bundle.",
            "Call techtree_publication_show with the same bundle_digest to read the entry and withdrawal receipt."
          )
        else
          {:ok, Jason.decode!(entry.submission_bytes)}
        end

      {:ok, :error} ->
        refused(
          "publication_missing",
          "No published Result has that bundle digest.",
          "Call techtree_publications to list available bundle digests."
        )

      :database_down ->
        refused("unavailable", "Techtree results are unavailable.", "Try again in a moment.")
    end
  end

  defp fetch_entry_with_runs(digest) do
    with {:ok, entry} <- Query.get_entry(digest) do
      {:ok, entry, Query.runs_behind(entry)}
    end
  end

  defp read_skill(digest) do
    case Outage.read(fn -> Query.skill(digest) end) do
      {:ok, {:ok, answer}} ->
        bytes = Projection.skill(answer)
        {:ok, Jason.decode!(bytes)}

      {:ok, :error} ->
        refused(
          "skill_not_found",
          "No standing published Result carries that Skill digest.",
          "Call techtree_publications to find published Skills."
        )

      :database_down ->
        refused("unavailable", "Techtree skills are unavailable.", "Try again in a moment.")
    end
  end

  defp refused(code, message, hint) do
    body = %{error: %{code: to_string(code), message: message, hint: hint}}
    {:error, Refused.exception(body: body)}
  end

  defp maybe_put_before(params, nil), do: params

  defp maybe_put_before(params, seq) when is_integer(seq),
    do: Map.put(params, "before_sequence", Integer.to_string(seq))

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value) when is_binary(value), do: Map.put(params, key, value)
end

defimpl AshAi.ToToolError, for: RegentsWeb.Techtree.AgentTools.Public.Refused do
  def to_tool_error(%{body: body}), do: Jason.encode!(body)
end
