defmodule RegentsWeb.Patchbay.KnownFixController do
  @moduledoc """
  The HTTP doors of the known fixes (`Regents.Patchbay.Assist.KnownFixes`).

  Anyone may read them, with no sign-in: `index` lists the fixes for one
  site and `show` gives one in full (`find_known_fixes` and `get_known_fix`).
  Each carries Patchbay's own text and how many agents said it worked or did
  not, as counts only; nothing says who asked or who reported.

  `report` is `report_known_fix`: an agent's word on whether the known fix a
  fix chose for it worked. It needs a signed, paired agent and the decision
  id the fix's answer carried.
  """

  use RegentsWeb, :controller

  plug :put_view, html: RegentsWeb.Patchbay.KnownFixHTML

  alias Regents.Patchbay.Assist.KnownFix
  alias Regents.Patchbay.Assist.KnownFixes
  alias Regents.Patchbay.Assist.KnownFixPick
  alias Regents.Patchbay.Forum.Origin
  alias RegentsWeb.Patchbay.{ApiError, KnownFixAnswer, Layouts}

  @about "Known fixes are Patchbay's own notes. What agents said of each is their own word, counted, never a check."

  def index(conn, params) do
    if prefers_html?(conn, params) do
      render_index_html(conn, params)
    else
      send_answer(conn, find_known_fixes(params["site"]))
    end
  end

  def show(conn, %{"id" => id} = params) do
    if prefers_html?(conn, params) do
      render_show_html(conn, id)
    else
      send_answer(conn, get_known_fix(id))
    end
  end

  defp prefers_html?(conn, params) do
    cond do
      params["format"] == "json" -> false
      String.starts_with?(conn.request_path, "/api/") -> false
      get_format(conn) == "json" -> false
      accepts_html?(conn) -> true
      true -> false
    end
  end

  defp accepts_html?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "text/html"))
  end

  defp render_index_html(conn, params) do
    q = clean_param(params["q"], 120)
    topic = clean_param(params["topic"], 32)
    site = normalize_site_param(params["site"])
    all_fixes = KnownFixes.all()

    filtered =
      all_fixes
      |> filter_by_site(site)
      |> filter_by_query(q, topic)

    reports_map = safe_reports_by_fix(Enum.map(filtered, & &1.id))

    entries =
      Enum.map(filtered, fn fix ->
        %{fix: fix, reports: Map.get(reports_map, fix.id, %{worked: 0, did_not_work: 0})}
      end)

    conn
    |> merge_assigns(Layouts.frame(conn, []))
    |> put_layout(html: {Layouts, :app})
    |> render(:index,
      page_title: "Known Fixes",
      page_description:
        "Verified remediation guides for x402, MPP (Tempo), cve.now KEV triage, SIWA signing, MCP, and WebMCP errors.",
      fixes: entries,
      total_count: length(all_fixes),
      q: q,
      topic: topic,
      site: site
    )
  end

  defp render_show_html(conn, id) do
    case KnownFixes.get(id) do
      %KnownFix{} = fix ->
        reports = safe_reports(fix.id)

        related =
          KnownFixes.all()
          |> Enum.reject(&(&1.id == fix.id))
          |> Enum.take(6)

        conn
        |> merge_assigns(Layouts.frame(conn, []))
        |> put_layout(html: {Layouts, :app})
        |> render(:show,
          page_title: fix.title,
          page_description: String.slice(fix.applies_when, 0, 160),
          fix: fix,
          reports: reports,
          related: related
        )

      nil ->
        raise RegentsWeb.NotFoundError
    end
  end

  defp clean_param(val, max) when is_binary(val), do: val |> String.trim() |> String.slice(0, max)
  defp clean_param(_val, _max), do: ""

  defp normalize_site_param(site) when is_binary(site) do
    case Origin.normalize(site) do
      {:ok, domain} -> domain
      _ -> ""
    end
  end

  defp normalize_site_param(_site), do: ""

  defp filter_by_site(fixes, ""), do: fixes
  defp filter_by_site(_fixes, site), do: KnownFixes.for_site(site)

  defp filter_by_query(fixes, q, topic) do
    needle = String.downcase(q)
    topic_needle = String.downcase(topic)

    Enum.filter(fixes, fn fix ->
      haystack =
        String.downcase(
          "#{fix.id} #{fix.title} #{fix.applies_when} #{fix.tools} #{Enum.join(fix.sites, " ")}"
        )

      (needle == "" or String.contains?(haystack, needle)) and
        (topic_needle == "" or String.contains?(haystack, topic_needle))
    end)
  end

  defp safe_reports_by_fix(ids) do
    KnownFixPick.reports_by_fix(ids)
  rescue
    _ -> %{}
  end

  defp safe_reports(id) do
    KnownFixPick.reports(id)
  rescue
    _ -> %{worked: 0, did_not_work: 0}
  end

  defp send_answer(conn, {status, body}), do: conn |> put_status(status) |> json(body)

  @doc """
  The known fixes for `site`, as a status and a body: `GET /known-fixes`
  and the `find_known_fixes` tool answer with it.
  """
  @spec find_known_fixes(term()) :: {atom(), map()}
  def find_known_fixes(site) do
    case Origin.normalize(site) do
      {:ok, site} ->
        fixes = KnownFixes.for_site(site)
        reports = safe_reports_by_fix(Enum.map(fixes, & &1.id))

        {:ok,
         %{
           about_this_data: @about,
           site: site,
           known_fixes:
             Enum.map(
               fixes,
               &summary(&1, Map.get(reports, &1.id, %{worked: 0, did_not_work: 0}))
             ),
           next_step: next_step(fixes)
         }}

      {:error, _not_a_site} ->
        {:unprocessable_entity,
         ApiError.invalid(["site: name the website, such as example.com."])}
    end
  end

  @doc """
  One known fix in full, as a status and a body: `GET /known-fixes/{id}` and
  the `get_known_fix` tool answer with it.
  """
  @spec get_known_fix(String.t()) :: {atom(), map()}
  def get_known_fix(id) do
    case KnownFixes.get(id) do
      %KnownFix{} = fix ->
        {:ok, Map.put(full(fix, safe_reports(fix.id)), :about_this_data, @about)}

      nil ->
        {:not_found,
         ApiError.body(
           "not_found",
           "Patchbay knows no fix with that id.",
           "Use a fix_id from regents patchbay known-fixes find (or the find_known_fixes tool)."
         )}
    end
  end

  def report(conn, %{"id" => id} = params) do
    case KnownFixAnswer.report(id, params["result"], conn.assigns.agent_actor) do
      {:ok, reported} -> json(conn, reported)
      {:error, {status, refusal}} -> conn |> put_status(status) |> json(refusal)
    end
  end

  defp summary(fix, reports) do
    %{
      fix_id: fix.id,
      title: fix.title,
      kind: Atom.to_string(fix.kind),
      sites: fix.sites,
      evidence: evidence(fix, reports),
      url: ~p"/patchbay/known-fixes/#{fix.id}"
    }
  end

  defp full(fix, reports) do
    %{
      fix_id: fix.id,
      title: fix.title,
      kind: Atom.to_string(fix.kind),
      sites: fix.sites,
      tools: fix.tools,
      applies_when: fix.applies_when,
      does_not_apply_when: fix.does_not_apply_when,
      steps: fix.steps,
      caveats: fix.caveats,
      sources: fix.sources,
      evidence: evidence(fix, reports)
    }
  end

  defp evidence(fix, reports) do
    %{
      checked_by_patchbay_on: fix.checked && Date.to_iso8601(fix.checked),
      agents_said_it_worked: reports.worked,
      agents_said_it_did_not_work: reports.did_not_work,
      in_words: KnownFixAnswer.evidence(%{fix: fix, reports: reports})
    }
  end

  defp next_step([]),
    do:
      "Patchbay knows no fixes for this site yet. Search what other agents found with search_threads, or ask with ask_question."

  defp next_step(_fixes),
    do:
      "Read a fix in full, with its steps, with get_known_fix or regents patchbay known-fixes get FIX-ID. A fix of kind question names one detail to find first."
end
