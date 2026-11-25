defmodule RegentsWeb.Techtree.Plugs.PageMarkdown do
  @moduledoc """
  The Markdown answer of Techtree's public pages built from the database, from
  release files or from their LiveView's own data: Techtree home, Results, each
  Result, each Climb, the Wallet Bench and each wallet test, the Blog and each
  post, the service pages under `/techtree/services`, Techtree Formal, the tdd
  example, and each Skill comparison. Static Techtree guides are answered before
  the router by `RegentsWeb.PublicDocuments`; these wait for the router, so an
  HTML request reads nothing here and a Markdown one reads only what its page
  reads.
  """

  @behaviour Plug

  import Plug.Conn

  alias Regents.Techtree.Catalog.Query, as: Catalog
  alias Regents.Techtree.Network.Query
  alias Regents.Techtree.Train.Comparisons
  alias Regents.Techtree.WalletBench
  alias Regents.Techtree.WalletBench.Catalog, as: BenchCatalog
  alias RegentsWeb.NotFoundError

  alias RegentsWeb.Techtree.{
    Blog,
    BlogController,
    CampaignFacts,
    ClimbCopy,
    ClimbsLive,
    FormalLive,
    HomeLive,
    ModelAccess,
    Outage,
    PublicDocuments,
    RunsLive,
    ServiceLive,
    TddShowcase,
    TddShowcaseLive,
    TrainCopy,
    TrainLive,
    TrainMD,
    WalletBenchController,
    WalletBenchCopy,
    WalletBenchLive
  }

  @pages %{
    HomeLive => :home,
    RunsLive.Index => :results,
    RunsLive.Show => :result,
    ClimbsLive.Show => :climb,
    WalletBenchLive.Index => :wallet_bench,
    WalletBenchLive.Show => :wallet_bench_show,
    ServiceLive => :service,
    FormalLive => :formal,
    TddShowcaseLive => :tdd,
    TrainLive.Show => :train_comparison
  }

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case {Phoenix.Controller.get_format(conn), page(conn)} do
      {"md", nil} ->
        raise Phoenix.NotAcceptableError,
          message: "this page has no Markdown",
          accepts: ["html"]

      {"md", :wallet_bench} ->
        conn |> WalletBenchController.markdown(%{}) |> halt()

      {"md", :wallet_bench_show} ->
        send_wallet_bench_show(conn)

      {"md", page} ->
        # Markdown is rendered from committed copy and database fields as text/markdown.
        # sobelow_skip ["XSS.SendResp"]
        conn
        |> Phoenix.Controller.put_secure_browser_headers()
        |> put_resp_content_type("text/markdown", "utf-8")
        |> send_resp(200, markdown(page, conn) <> PublicDocuments.trailer())
        |> halt()

      _html ->
        conn
    end
  end

  defp page(conn) do
    case {conn.private[:phoenix_live_view], conn.private[:phoenix_controller],
          conn.private[:phoenix_action]} do
      {{view, _opts, _session}, _controller, _action} -> Map.get(@pages, view)
      {nil, BlogController, :index} -> :blog_index
      {nil, BlogController, :show} -> :blog_show
      _other -> nil
    end
  end

  defp send_wallet_bench_show(%{path_params: %{"id" => id}} = conn) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, attempt} when not is_nil(attempt) <-
           Outage.read(fn ->
             WalletBench.get_attempt!(uuid,
               load: [:machine, :turns, :model_spend_usd, :judge_cost_usd],
               not_found_error?: false
             )
           end) do
      # Markdown is rendered from bench metadata and stored rulings as text/markdown.
      # sobelow_skip ["XSS.SendResp"]
      conn
      |> Phoenix.Controller.put_secure_browser_headers()
      |> put_resp_content_type("text/markdown", "utf-8")
      |> send_resp(200, wallet_bench_attempt(attempt) <> PublicDocuments.trailer())
      |> halt()
    else
      :database_down ->
        conn
        |> put_resp_header("retry-after", "30")
        |> put_resp_content_type("text/markdown", "utf-8")
        |> send_resp(503, WalletBenchCopy.unreadable() <> "\n")
        |> halt()

      _missing ->
        raise NotFoundError, "no wallet test has that number"
    end
  end

  defp markdown(:home, _conn), do: HomeLive.markdown()

  defp markdown(:results, conn) do
    case Query.read_page_options(conn.query_params) do
      {:ok, options} -> results(Query.page(options), options)
      {:error, reason} -> raise Plug.BadRequestError, message: reason
    end
  end

  defp markdown(:result, %{path_params: %{"bundle_digest" => digest}}) do
    case Query.get_entry(digest) do
      {:ok, entry} -> result(entry)
      :error -> raise NotFoundError, "no run is published under that fingerprint"
    end
  end

  defp markdown(:climb, %{path_params: %{"slug" => slug}}) do
    case Catalog.get_climb_by_slug(slug) do
      {:ok, climb} -> climb(climb)
      {:error, _error} -> raise NotFoundError, "no Climb is published under that name"
    end
  end

  defp markdown(:tdd, _conn), do: tdd(TddShowcase.load!(TddShowcase.folder()))

  defp markdown(:train_comparison, %{path_params: %{"slug" => slug}}) do
    case Comparisons.fetch(slug) do
      {:ok, comparison} -> TrainMD.show(comparison)
      :error -> raise NotFoundError, "no comparison has that name"
    end
  end

  defp markdown(:service, %{private: %{phoenix_live_view: {_view, opts, _session}}}),
    do: opts |> Keyword.fetch!(:action) |> ServiceLive.markdown()

  defp markdown(:formal, _conn) do
    PublicDocuments.formal()
    |> String.replace("{{frontier}}", FormalLive.frontier_markdown())
    |> String.replace("{{mailto}}", FormalLive.mailto())
  end

  defp markdown(:blog_index, _conn) do
    posts =
      case Blog.all() do
        [] -> raise NotFoundError, "no blog posts are published yet"
        list -> Enum.map_join(list, "\n", &blog_row/1)
      end

    """
    # Techtree Blog

    Findings from Techtree's evaluations and Agent Wallet Bench runs.

    #{posts}
    """
  end

  defp markdown(:blog_show, %{path_params: %{"slug" => slug}}) do
    case Blog.get(slug) do
      nil ->
        raise NotFoundError, "no blog post has that slug"

      post ->
        """
        # #{post.title}

        By #{post.author} · #{Calendar.strftime(post.date, "%-d %b %Y")}

        #{post.markdown}
        """
    end
  end

  defp blog_row(post) do
    summary = if post.description != "", do: ": " <> post.description, else: ""
    "- [#{post.title}](/techtree/blog/#{post.slug}) (#{Date.to_iso8601(post.date)})#{summary}"
  end

  defp wallet_bench_attempt(attempt) do
    turns =
      Enum.map_join(attempt.turns, "\n\n", fn turn ->
        ruling =
          if turn.judgment do
            "Outcome: #{WalletBenchCopy.outcome(turn.judgment)}."
          else
            "State: #{WalletBenchCopy.turn_state(turn.state)}."
          end

        files =
          turn.evidence
          |> Kernel.||(%{})
          |> Map.keys()
          |> Enum.sort()
          |> Enum.map_join("\n", fn file ->
            encoded = URI.encode(file, &URI.char_unreserved?/1)
            folder = BenchCatalog.turn_name(turn.test)
            "- [#{file}](/techtree/wallet-bench/#{attempt.id}/evidence/#{folder}/#{encoded})"
          end)

        files_block = if files == "", do: "", else: "\n\nRecorded files:\n\n#{files}"

        """
        ## #{WalletBenchCopy.test(turn.test)}

        #{ruling}#{files_block}
        """
        |> String.trim()
      end)

    """
    # #{WalletBenchCopy.pair(attempt)} · Wallet Bench

    - Status: #{WalletBenchCopy.status(attempt.state)}
    - Started: #{Calendar.strftime(attempt.inserted_at, "%d %b %Y %H:%M")} UTC
    - Model cost: #{WalletBenchCopy.dollars(attempt.model_spend_usd)}
    - Judge cost: #{WalletBenchCopy.dollars(attempt.judge_cost_usd)}
    - JSON summary: [/techtree/wallet-bench/#{attempt.id}/results.json](/techtree/wallet-bench/#{attempt.id}/results.json)
    - Zip archive: [/techtree/wallet-bench/#{attempt.id}/results.zip](/techtree/wallet-bench/#{attempt.id}/results.zip)

    #{turns}
    """
  end

  defp results(%{entries: entries, next_before_sequence: next}, options) do
    rows =
      case entries do
        [] -> "No Results are published here yet."
        entries -> Enum.map_join(entries, "\n", &result_row/1)
      end

    more =
      if next,
        do: "\n\n[Older Results](#{results_url(options, next)})",
        else: ""

    comparisons = Enum.map_join(Comparisons.list(), "\n", &comparison_row/1)

    """
    # Published Results

    Every Climb run somebody has published, newest first. This site checked that each receipt is consistent and signed by the key it names; it did not watch the run or repeat it. Each Result's bundle can be checked offline with `regents techtree proof verify`: [how to check a Result](/techtree/docs/verify). The same log as JSON: [/api/v1/techtree/publications](/api/v1/techtree/publications).

    #{rows}#{more}

    ## Comparisons

    Demonstrations Techtree ran itself on public Skills: the Skill as published against the revision chosen to improve it, on final-test cases kept apart from the improvement, with the same agent and settings. When the test does not establish a difference between the two versions, we report the result as inconclusive. They are not signed; each page offers its report to download: [how to check them](/techtree/docs/verify#blog-section-skill-comparisons).

    #{comparisons}

    ## More

    - [Wallet Bench](/techtree/wallet-bench): which agent can use which wallet.
    - [Formal](/techtree/formal): proofs that a precise model of your code keeps a stated property.
    """
  end

  defp comparison_row(comparison) do
    "- [#{comparison.skill.name}](/techtree/train/#{comparison.slug}): " <>
      "Original #{TrainCopy.figure(comparison.final.original)} → " <>
      "Revised #{TrainCopy.figure(comparison.final.improved)} · #{TrainCopy.verdict_name(comparison)}"
  end

  defp results_url(options, next) do
    options
    |> Keyword.put(:before_sequence, next)
    |> Regents.Techtree.Network.AgentVersions.url()
  end

  defp result_row(entry) do
    withdrawn = if Query.withdrawn?(entry), do: " Withdrawn.", else: ""

    "- [#{entry.campaign_name}](/techtree/results/#{entry.bundle_digest}): " <>
      "#{score(entry.baseline_mean)} without the Skill and #{score(entry.candidate_mean)} with it, " <>
      "#{entry.subject_model} on #{entry.subject_harness}. " <>
      "Published #{Calendar.strftime(entry.accepted_at, "%d %b %Y")}.#{withdrawn}"
  end

  defp result(entry) do
    withdrawn =
      if Query.withdrawn?(entry),
        do:
          "\nThis Result was withdrawn on #{date(entry.withdrawn_at)}; its bundle is no longer offered.\n",
        else: ""

    skill =
      if entry.skill_name,
        do: "- Skill: #{entry.skill_name} (the publisher gave this name; nothing checked it)\n",
        else: ""

    """
    # #{entry.campaign_name} · Published Result
    #{withdrawn}
    - Mean score: #{score(entry.baseline_mean)} without the Skill, #{score(entry.candidate_mean)} with it
    - Tasks: #{entry.wins} better, #{entry.losses} worse, #{entry.ties} the same, of #{entry.task_count}
    - Agent: #{entry.subject_harness} #{entry.subject_harness_version}, #{entry.subject_model} on #{entry.subject_provider}
    #{skill}- Checks this site ran on the receipt: #{entry.verification_checks_passed} of #{entry.verification_checks_run} passed
    - Published: #{date(entry.accepted_at)}
    - Runs behind it: #{Query.runs_behind(entry)}

    This site checked that the receipt is consistent and signed by the key it names. It did not watch the run and did not repeat it. Check the bundle yourself, offline:

    ```sh
    regents techtree proof verify path/to/result-bundle
    ```

    The bundle: [/api/v1/techtree/publications/#{entry.bundle_digest}/bundle](/api/v1/techtree/publications/#{entry.bundle_digest}/bundle). The record as JSON: [/api/v1/techtree/publications/#{entry.bundle_digest}](/api/v1/techtree/publications/#{entry.bundle_digest}).
    """
  end

  defp climb(climb) do
    copy = ClimbCopy.for_reference(climb.reference)
    trial = CampaignFacts.trial!(climb)

    scope = if copy, do: "\n#{copy.scope}\n", else: ""
    question = if copy, do: "- Question: #{copy.question}\n", else: ""

    """
    # #{climb.title}
    #{scope}
    #{question}- Tasks: #{climb.projection["task_count"]}, fixed before either Run
    - Model: `#{trial.model_id}`, run on #{ModelAccess.destinations(trial.routes)}
    - Reference: `#{climb.reference}`

    Each Run works the same tasks without the Skill and with it. Run `regents techtree climb show #{climb.reference}` for this Climb's next steps, after installing the release [Run locally](/techtree/docs/run-locally) names. Published Results from it are at [Results](/techtree/results).
    """
  end

  defp tdd(showcase) do
    claims =
      Enum.map_join(showcase.claims, "\n", fn claim ->
        "- #{claim.statement} (#{length(claim.tasks)} tasks)"
      end)

    """
    # #{showcase.skill.name} vs No Skill

    A local comparison of the #{showcase.skill.name} Skill against no Skill, reported by the person who ran it on #{date(showcase.created_at)}. Nothing here is signed: it is one comparison on one computer.

    - Held-out tasks: #{verdict(showcase.held_out.verdict)}, #{part(showcase.held_out)}
    - Tasks an improving agent may study: #{verdict(showcase.study.verdict)}, #{part(showcase.study)}
    - Model: `#{showcase.model.model_id}` on #{showcase.model.provider}
    - Skill licence: #{showcase.skill.licence.name}. #{showcase.skill.licence.copyright}

    ## Claims

    #{claims}

    The task files: [#{TddShowcase.export_url()}](#{TddShowcase.export_url()}).
    """
  end

  defp part(part),
    do:
      "#{part.wins} better, #{part.losses} worse, #{part.ties} the same, #{part.unresolved} unresolved"

  defp verdict(:improved), do: "improved"
  defp verdict(:regressed), do: "regressed"
  defp verdict(:mixed), do: "mixed"
  defp verdict(:no_difference), do: "no difference"
  defp verdict(:inconclusive), do: "inconclusive"

  defp score(nil), do: "no score"
  defp score(mean), do: :erlang.float_to_binary(mean / 1, decimals: 3)

  defp date(datetime), do: Calendar.strftime(datetime, "%d %b %Y")
end
