defmodule RegentsWeb.Patchbay.Search do
  @moduledoc "Public Patchbay matches for the shared workspace search and terminal."

  import RegentsWeb.Patchbay.Forum.BoardHTML,
    only: [
      site_name: 1,
      site_domain: 1,
      site_path: 1,
      tool_path: 2,
      tool_count: 1,
      tool_count_label: 3
    ]

  import Regents.Patchbay.Forum.PostSummary, only: [post_title: 1]

  alias Regents.Patchbay.Assist.KnownFixes
  alias Regents.Patchbay.Commerce.Catalog
  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Incidents
  alias Regents.Patchbay.Playbooks
  alias RegentsWeb.Patchbay.{Forum.Board, IncidentHTML}

  @doc "Searches public questions, sites, tools, and terminal reference material."
  def matches(q) do
    with {:ok, page} <- Forum.search_threads(q, page: [limit: 6], load: [:site]),
         {:ok, %{sites: sites, tools: tools}} <- Board.matches(q) do
      {:ok,
       Enum.map(page.results, &question/1) ++
         Enum.map(Enum.take(sites, 4), &site/1) ++
         Enum.map(Enum.take(tools, 4), &tool/1) ++ terminal(q)}
    end
  end

  defp question(post),
    do:
      item(
        :question,
        post_title(post),
        PostAddress.path(post),
        if(post.site, do: site_name(post.site), else: "Thread")
      )

  defp site(site) do
    detail =
      site_domain(site) <>
        " · " <> tool_count_label(tool_count(site), "WebMCP tool", "WebMCP tools")

    item(:site, site_name(site), site_path(site), detail)
  end

  defp tool(tool),
    do: item(:tool, tool.name, tool_path(tool.site, tool.name), site_name(tool.site))

  defp item(kind, label, path, detail),
    do: %{kind: kind, label: label, path: path, detail: detail, product: "patchbay", fallback: 7}

  def cve_matches_query?(_post, _facts, ""), do: true

  def cve_matches_query?(post, facts, q) do
    haystack =
      [
        post.cve_now_id,
        post.title,
        facts && facts.product,
        Enum.join((facts && facts.ecosystems) || [], " ")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, q)
  end

  def filter_incidents(incidents, q) do
    needle = String.downcase(String.trim(q || ""))

    if needle == "" do
      incidents
    else
      Enum.filter(incidents, fn inc ->
        haystack =
          String.downcase("#{inc.name} #{inc.title} #{inc.summary} #{inc.post_site} #{inc.tag}")

        String.contains?(haystack, needle)
      end)
    end
  end

  def filter_known_fixes(fixes, q, protocol) do
    q = String.downcase(q || "")
    proto = String.downcase(protocol || "")

    Enum.filter(fixes, fn fix ->
      haystack = String.downcase("#{fix.id} #{fix.title} #{fix.applies_when} #{fix.tools}")

      (q == "" or String.contains?(haystack, q)) and
        (proto == "" or String.contains?(haystack, proto))
    end)
  end

  defp terminal(q) do
    cves =
      case Forum.list_cve_now_posts(page: [limit: 50]) do
        {:ok, %{results: posts}} -> posts
        _ -> []
      end

    needle = String.downcase(q || "")

    matched_cves =
      cves
      |> Enum.filter(&cve_matches_query?(&1, &1.cve_facts, needle))
      |> Enum.take(4)
      |> Enum.map(fn post ->
        %{
          label: post.cve_now_id,
          meta: (post.cve_facts && post.cve_facts.product) || IncidentHTML.cve_title(post),
          href: PostAddress.path(post)
        }
      end)

    matched_incidents =
      if matched_cves == [] do
        Incidents.active()
        |> filter_incidents(needle)
        |> Enum.take(3)
        |> Enum.map(fn inc ->
          %{
            label: inc.title,
            meta: inc.post_site,
            href: "/patchbay/incidents/#{inc.name}"
          }
        end)
      else
        []
      end

    matched_services =
      Catalog.filter(%{"q" => needle})
      |> Enum.take(5)
      |> Enum.map(fn svc ->
        %{
          label: svc["name"],
          meta: "#{svc["domain"]} · #{svc["avg_price"]}",
          href: "/patchbay/#{svc["domain"]}"
        }
      end)

    matched_playbooks =
      Playbooks.search(needle)
      |> Enum.take(4)
      |> Enum.map(fn pb ->
        %{
          label: pb.title,
          meta: pb.estimated_cost,
          href: "/patchbay/playbooks/#{pb.slug}"
        }
      end)

    matched_fixes =
      filter_known_fixes(KnownFixes.all(), needle, "")
      |> Enum.take(4)
      |> Enum.map(fn fix ->
        %{label: fix.title, meta: fix.id, href: "/patchbay/known-fixes/#{fix.id}"}
      end)

    Enum.map(
      matched_cves ++ matched_incidents ++ matched_services ++ matched_playbooks ++ matched_fixes,
      &item(:page, &1.label, &1.href, &1.meta)
    )
  end
end
