defmodule AshPlatform.Techtree.UpliftReport do
  @moduledoc """
  Deterministic human projection of the canonical UpliftReport payload.

  This module never stores or rewrites a report. The fetched JSON remains the
  only report shape; this result is a short-lived rendering model.
  """

  @outcome_labels %{
    "positive" => "Helped",
    "null" => "No measurable change",
    "negative" => "Hurt performance",
    "inconclusive" => "Could not tell",
    "invalid" => "Run invalid"
  }
  @outcomes Map.keys(@outcome_labels)

  @spec project(map()) :: {:ok, map()} | :not_uplift_report
  def project(report) when is_map(report) do
    with {:ok, outcome} <- required_string(report, "outcome", @outcomes),
         {:ok, evidence_class} <- required_string(report, "evidence_class", nil),
         {:ok, reproduction_status} <- required_string(report, "reproduction_status", nil),
         {:ok, package_status} <-
           required_string(report, "reproduction_package_status", ["available", "absent"]),
         final_capability when not is_nil(final_capability) <-
           first_present(report, ["final_capability_level", "final_capability_summary"]),
         measured_change when not is_nil(measured_change) <-
           first_present(report, ["measured_change", "measured_change_summary"]) do
      {:ok,
       %{
         outcome: %{value: outcome, label: Map.fetch!(@outcome_labels, outcome)},
         final_capability: final_capability,
         measured_change: measured_change,
         regressions: value_or(report, ["regressions", "regression_summary"], []),
         cost_latency:
           value_or(report, ["cost_latency", "cost_summary", "latency_summary"], "Not recorded."),
         evidence: %{
           class: evidence_class_label(evidence_class),
           reproduction_status: reproduction_status_label(reproduction_status),
           reproduction_package: package_label(package_status)
         },
         scored_evaluation: Map.get(report, "scored_evaluation"),
         calibration: calibration(report),
         inspect_evidence: inspect_evidence(report)
       }}
    else
      _result -> :not_uplift_report
    end
  end

  def project(_report), do: :not_uplift_report

  defp required_string(report, key, allowed) do
    case Map.get(report, key) do
      value when is_binary(value) ->
        if is_nil(allowed) or value in allowed, do: {:ok, value}, else: :error

      _value ->
        :error
    end
  end

  defp first_present(report, keys) do
    case Enum.find(keys, &(Map.has_key?(report, &1) and not is_nil(Map.get(report, &1)))) do
      nil -> nil
      key -> Map.get(report, key)
    end
  end

  defp value_or(report, keys, fallback) do
    case first_present(report, keys) do
      nil -> fallback
      value -> value
    end
  end

  defp evidence_class_label("single_run"), do: "Single run"
  defp evidence_class_label(value), do: humanize(value)

  defp reproduction_status_label("not_run"), do: "Reproduction not run"
  defp reproduction_status_label(value), do: humanize(value)

  defp package_label("available"), do: "Reproduction package included"
  defp package_label("absent"), do: "Reproduction package not available"

  defp inspect_evidence(report) do
    report
    |> Map.take([
      "schema_version",
      "report_id",
      "evidence_class",
      "comparison",
      "receipt_bindings",
      "decision_rule",
      "reproduction_status",
      "reproduction_package_status",
      "arms",
      "uncertainty",
      "disclosures",
      "limitations",
      "freshness",
      "decision_sentence"
    ])
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp calibration(report) do
    case Map.get(report, "calibration") do
      calibration when is_map(calibration) ->
        Map.put_new(
          calibration,
          "warning",
          "Possible contamination: public-reference scores do not carry the uplift claim."
        )

      value ->
        value
    end
  end

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize(_value), do: "Not recorded"
end
