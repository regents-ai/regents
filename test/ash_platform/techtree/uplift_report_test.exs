defmodule AshPlatform.Techtree.UpliftReportTest do
  use ExUnit.Case, async: true

  alias AshPlatform.Techtree.UpliftReport

  @outcomes %{
    "positive" => "Helped",
    "null" => "No measurable change",
    "negative" => "Hurt performance",
    "inconclusive" => "Could not tell",
    "invalid" => "Run invalid"
  }

  test "projects every canonical outcome into its human presentation" do
    for {outcome, label} <- @outcomes do
      assert {:ok, report} = UpliftReport.project(base_report(outcome))
      assert report.outcome == %{value: outcome, label: label}
    end
  end

  test "keeps final capability beside measured change" do
    assert {:ok, report} = UpliftReport.project(base_report("positive"))
    assert report.final_capability == "advanced"
    assert report.measured_change == "+2 held-out tasks"
  end

  test "keeps calibration separate and adds its contamination warning" do
    assert {:ok, report} = UpliftReport.project(base_report("positive"))
    assert report.scored_evaluation == %{"held_out" => %{"delta" => 2}}
    assert report.calibration["scores"] == %{"public_reference" => 1}
    assert report.calibration["warning"] =~ "Possible contamination"
  end

  test "renders absent calibration honestly" do
    report = Map.delete(base_report("null"), "calibration")

    assert {:ok, projected} = UpliftReport.project(report)
    assert projected.calibration == nil
  end

  test "uses structural evidence fields for the evidence presentation" do
    report = base_report("positive")

    assert {:ok, projected} = UpliftReport.project(report)

    assert projected.evidence == %{
             class: "Single run",
             reproduction_status: "Reproduction not run",
             reproduction_package: "Reproduction package included"
           }

    assert projected.inspect_evidence["evidence_class"] == "single_run"
    assert projected.inspect_evidence["reproduction_status"] == "not_run"
    assert projected.inspect_evidence["reproduction_package_status"] == "available"
  end

  test "does not project malformed canonical reports" do
    assert UpliftReport.project(%{"outcome" => "positive"}) == :not_uplift_report
  end

  defp base_report(outcome) do
    %{
      "schema_version" => "uplift-report-v1",
      "report_id" => "report-001",
      "outcome" => outcome,
      "final_capability_level" => "advanced",
      "measured_change" => "+2 held-out tasks",
      "evidence_class" => "single_run",
      "reproduction_status" => "not_run",
      "reproduction_package_status" => "available",
      "cost_latency" => "$1.84 / 42 seconds",
      "scored_evaluation" => %{"held_out" => %{"delta" => 2}},
      "calibration" => %{"scores" => %{"public_reference" => 1}}
    }
  end
end
