defmodule AshPlatform.Techtree.UpliftReportTest do
  use ExUnit.Case, async: true

  alias AshPlatform.Techtree.UpliftReport
  alias AshPlatform.Test.UpliftReportFixture

  test "projects every canonical outcome into its human presentation" do
    labels = %{
      "positive" => "Helped",
      "null" => "No measurable change",
      "negative" => "Hurt performance",
      "inconclusive" => "Could not tell",
      "invalid" => "Run invalid"
    }

    for {outcome, label} <- labels do
      report =
        UpliftReportFixture.canonical_report(outcome: outcome)

      assert {:ok, projected} = UpliftReport.project(report)
      assert projected.outcome == %{value: outcome, label: label}
    end
  end

  test "keeps final capability beside measured change in the projection" do
    assert {:ok, report} = UpliftReport.project(UpliftReportFixture.canonical_report())

    assert report.final_capability == %{
             "scale" => "score_millis",
             "baseline" => 500,
             "candidate" => 700
           }

    assert report.measured_change == %{
             "absolute_delta_millis" => 200,
             "relative_error_reduction_millis" => 400
           }
  end

  test "keeps calibration separate and preserves its contamination warning" do
    assert {:ok, report} = UpliftReport.project(UpliftReportFixture.canonical_report())
    assert report.scored_evaluation["provenance"] == "held_out"
    assert report.calibration["provenance"] == "public_reference"
    assert report.calibration["possible_contamination"] == "possible-contamination"
    assert report.calibration["warning"] =~ "Possible contamination"
  end

  test "rejects public-reference scores without the contamination stamp" do
    report =
      UpliftReportFixture.canonical_report()
      |> update_in(["calibration", "possible_contamination"], fn _value -> nil end)
      |> UpliftReportFixture.rekey()

    refute match?({:ok, _projection}, UpliftReport.project(report))
  end

  test "rejects held-out scores carrying a contamination stamp" do
    report =
      UpliftReportFixture.canonical_report()
      |> update_in(["scored_evaluation", "possible_contamination"], fn _value ->
        "possible-contamination"
      end)
      |> UpliftReportFixture.rekey()

    refute match?({:ok, _projection}, UpliftReport.project(report))
  end

  test "requires the exact 23-field canonical top-level shape" do
    report = UpliftReportFixture.canonical_report()
    truncated = Map.delete(report, "action_receipt")

    assert map_size(report) == 23
    assert UpliftReport.project(truncated) == :not_uplift_report
  end

  test "rejects the review probe's lookalike evidence vocabulary" do
    report =
      UpliftReportFixture.canonical_report()
      |> Map.merge(%{
        "evidence_class" => "verified_effective",
        "reproduction_status" => "guaranteed"
      })
      |> UpliftReportFixture.rekey()

    assert UpliftReport.project(report) == :not_uplift_report
  end

  test "rejects unknown outcomes" do
    report =
      UpliftReportFixture.canonical_report()
      |> Map.put("outcome", "guaranteed")
      |> UpliftReportFixture.rekey()

    assert UpliftReport.project(report) == :not_uplift_report
  end

  test "rejects an invalid schema version" do
    report =
      UpliftReportFixture.canonical_report()
      |> Map.put("schema_version", 2)
      |> UpliftReportFixture.rekey()

    assert UpliftReport.project(report) == :not_uplift_report
  end

  test "rejects duplicate JSON object fields before projection" do
    report = UpliftReportFixture.canonical_report() |> Jason.encode!()
    assert report =~ ~s("outcome":"positive")

    duplicate =
      String.replace(
        report,
        ~s("outcome":"positive"),
        ~s("outcome":"positive","outcome":"positive"),
        global: false
      )

    assert UpliftReport.project_json(duplicate) == :not_uplift_report
  end

  test "uses sorted canonical JSON for report identity" do
    assert UpliftReport.expected_report_id(%{
             "report_id" => "ignored",
             "action_receipt" => %{},
             "b" => 1,
             "a" => %{"d" => 2, "c" => 3}
           }) == "uplift-report-1acbc30524acbadd8e09810b"
  end
end
