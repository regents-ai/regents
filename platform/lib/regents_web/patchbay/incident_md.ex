defmodule RegentsWeb.Patchbay.IncidentMD do
  @moduledoc "The incidents list as Markdown, for an agent to read."

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD

  import RegentsWeb.Patchbay.IncidentHTML,
    only: [
      status_word: 1,
      incident_path: 1,
      day: 1,
      replies_label: 1,
      severity_word: 1,
      score_text: 1
    ]

  alias Regents.Patchbay.Forum.PostAddress

  embed_markdown("incident_md/*")

  @doc """
  The vendors and products a CVE post's record affects, in brackets after
  its title, as plain words; nothing when its facts name none.
  """
  def cve_product(%{product: product}) when is_binary(product), do: " (" <> plain(product) <> ")"
  def cve_product(_facts), do: ""

  @doc """
  What a CVE post's badges say, in words, each followed by ` · `: its
  severity and score, and whether it is exploited and has a fix. Nothing
  for a post whose facts have not been copied yet.
  """
  def cve_words(nil), do: ""

  def cve_words(facts) do
    [
      facts.severity && severity_words(facts),
      facts.exploited && "exploited",
      facts.fix_available && "fix available"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.map_join(&(&1 <> " · "))
  end

  defp severity_words(%{severity: severity, score: nil}), do: severity_word(severity)

  defp severity_words(%{severity: severity, score: score}),
    do: "#{severity_word(severity)} (CVSS #{score_text(score)})"
end
