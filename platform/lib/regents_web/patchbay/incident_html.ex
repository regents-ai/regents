defmodule RegentsWeb.Patchbay.IncidentHTML do
  @moduledoc """
  The words a post copied from cve.now is shown in, the same wherever it is
  listed or opened. So far its badges on a question list's rows.
  """

  use RegentsWeb, :html

  attr :facts, :any, required: true, doc: "a CVE post's `cve_facts`, nil until they are copied"

  @doc """
  A post copied from cve.now as badges, the same wherever it is listed or
  opened: `CVE`, then its severity with its score, `Exploited` while CISA
  lists it, and `Fix available` once cve.now lists a fix. A post whose facts
  have not been copied yet shows `CVE` alone.
  """
  def cve_badges(assigns) do
    ~H"""
    <span class="pb-cve-badges">
      <span class="pb-cve-badge">CVE</span>
      <span
        :if={@facts && @facts.severity}
        class="pb-cve-badge"
        data-severity={@facts.severity}
      >{severity_label(@facts)}</span>
      <span :if={@facts && @facts.exploited} class="pb-cve-badge" data-tone="exploited">
        Exploited
      </span>
      <span :if={@facts && @facts.fix_available} class="pb-cve-badge" data-tone="fix">
        Fix available
      </span>
    </span>
    """
  end

  @doc ~S"""
  A CVE's severity as its badge reads, the level and the score:
  "Critical · 9.4", or the level alone when the record has no score.
  """
  def severity_label(%{severity: severity, score: nil}), do: severity_word(severity)

  def severity_label(%{severity: severity, score: score}),
    do: "#{severity_word(severity)} · #{score_text(score)}"

  @doc "A CVE severity level as a word."
  def severity_word(:critical), do: "Critical"
  def severity_word(:high), do: "High"
  def severity_word(:medium), do: "Medium"
  def severity_word(:low), do: "Low"
  def severity_word(:none), do: "None"

  @doc "A CVSS score to one decimal place, as cve.now writes it."
  def score_text(score), do: :erlang.float_to_binary(score, decimals: 1)
end
