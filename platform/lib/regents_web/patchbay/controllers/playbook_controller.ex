defmodule RegentsWeb.Patchbay.PlaybookController do
  @moduledoc """
  Agent Support Playbooks at `/patchbay/playbooks` and `/patchbay/playbooks/:slug`
  (plus `Accept: text/markdown` and `.md` endpoints). Mirrors `agentic.market`'s
  composable Bundles for commerce debugging, x402/MPP troubleshooting, and
  `cve.now` critical security triage.
  """

  use RegentsWeb, :controller

  alias Regents.Patchbay.Playbooks
  alias RegentsWeb.Patchbay.Layouts

  def index(conn, _params) do
    playbooks = Playbooks.all()

    if get_format(conn) == "md" do
      body =
        [
          "# Patchbay Agent Support Playbooks\n",
          Enum.map_join(playbooks, "\n\n", fn pb ->
            "## #{pb.title} (`#{pb.slug}`)\n\n" <>
              "- Pillar: #{pb.pillar}\n" <>
              "- Estimated cost: #{pb.estimated_cost}\n" <>
              "- Protocols: #{Enum.join(pb.protocols, ", ")}\n" <>
              "- URL: #{RegentsWeb.Endpoint.url()}/patchbay/playbooks/#{pb.slug}\n\n" <>
              pb.summary
          end)
        ]
        |> Enum.join("\n")

      conn
      |> put_resp_content_type("text/markdown")
      |> send_resp(200, body)
    else
      conn
      |> merge_assigns(
        [
          page_title: "Agent Support Playbooks",
          page_description:
            "Composable agent prompts and diagnostic checklists for x402, MPP (Tempo), agentic commerce, and cve.now active criticals."
        ] ++ Layouts.frame(conn, [])
      )
      |> put_view(html: RegentsWeb.Patchbay.PlaybookHTML)
      |> render(:index, playbooks: playbooks)
    end
  end

  def show(conn, %{"slug" => raw_slug}) do
    {slug, md_ext?} =
      if String.ends_with?(raw_slug, ".md"),
        do: {String.replace_suffix(raw_slug, ".md", ""), true},
        else: {raw_slug, false}

    case Playbooks.get(slug) do
      nil ->
        raise RegentsWeb.NotFoundError

      playbook ->
        if md_ext? or get_format(conn) == "md" do
          conn
          |> put_resp_content_type("text/markdown")
          |> send_resp(200, playbook.raw_markdown)
        else
          conn
          |> merge_assigns(
            [
              page_title: playbook.title,
              page_description: playbook.summary
            ] ++ Layouts.frame(conn, [])
          )
          |> put_view(html: RegentsWeb.Patchbay.PlaybookHTML)
          |> render(:show,
            playbook: playbook,
            others: Enum.reject(Playbooks.all(), &(&1.slug == slug))
          )
        end
    end
  end
end
