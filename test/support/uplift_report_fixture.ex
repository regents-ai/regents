defmodule AshPlatform.Test.UpliftReportFixture do
  alias AshPlatform.Techtree.UpliftReport

  @package_digest String.duplicate("e", 64)

  def canonical_report(opts \\ []) do
    calibration? = Keyword.get(opts, :calibration?, true)
    outcome = Keyword.get(opts, :outcome, "positive")

    receipt_bindings =
      [
        binding("task-held-out", "held_out", "c", "d")
      ] ++
        if(calibration?, do: [binding("task-public", "public_reference", "e", "f")], else: [])

    report = %{
      "schema_version" => 1,
      "report_id" => "pending",
      "comparison" => %{
        "receipt_digests" => [String.duplicate("a", 64), String.duplicate("b", 64)],
        "protocol_id" => "protocol-1",
        "family_id" => "family-1"
      },
      "arms" => [arm("baseline", "capsule-baseline"), arm("candidate", "capsule-candidate")],
      "receipt_bindings" => receipt_bindings,
      "decision_rule" => %{
        "primary_metric" => "score_millis",
        "minimum_valid_task_count" => 1,
        "positive_threshold_millis" => 10,
        "negative_threshold_millis" => -10,
        "null_band_millis" => 2,
        "severe_regression_rule" => %{"kind" => "delta_at_or_below", "threshold_millis" => 100},
        "inconclusive_conditions" => [
          "valid_task_count_below_minimum",
          "delta_between_thresholds"
        ],
        "invalid_conditions" => ["any_arm_not_completed", "missing_score"]
      },
      "scored_evaluation" => evaluation("held_out", "task-held-out", 500, 700, nil, true),
      "calibration" =>
        if(calibration?,
          do:
            evaluation(
              "public_reference",
              "task-public",
              800,
              800,
              "possible-contamination",
              false
            ),
          else: nil
        ),
      "outcome" => "positive",
      "final_capability_level" => %{
        "scale" => "score_millis",
        "baseline" => 500,
        "candidate" => 700
      },
      "measured_change" => %{
        "absolute_delta_millis" => 200,
        "relative_error_reduction_millis" => 400
      },
      "regressions" => %{
        "severe" => [],
        "non_severe" => [],
        "severe_count" => 0,
        "non_severe_count" => 0
      },
      "uncertainty" => %{
        "treatment" => "declared-point-delta",
        "point_delta_millis" => 200,
        "confidence_interval" => nil
      },
      "cost_latency" => %{
        "baseline" => %{
          "cost_usd_cents" => distribution([10]),
          "wall_time_ms" => distribution([100])
        },
        "candidate" => %{
          "cost_usd_cents" => distribution([12]),
          "wall_time_ms" => distribution([120])
        }
      },
      "disclosures" => %{"search_optimizer" => %{"method" => "manual", "candidate_count" => 1}},
      "limitations" => ["Local receipts are operator-trusted."],
      "freshness" => %{
        "status" => "fresh",
        "as_of" => "2030-01-01T00:00:00Z",
        "invalidation_triggers" => []
      },
      "evidence_class" => "single_run",
      "reproduction_status" => "not_run",
      "reproduction_package_status" => "available",
      "decision_sentence" =>
        "This skill improved held-out performance by 20 percentage points, ending at 70%, with no severe regressions.",
      "reproduction_package" => %{"algorithm" => "sha256", "digest" => @package_digest},
      "action_receipt" => %{
        "action_id" => "pending",
        "capability_id" => "techtree.uplift.report",
        "action_kind" => "uplift",
        "resource_type" => "uplift_report",
        "resource_id" => "pending",
        "status" => "completed",
        "idempotency_key" => "pending",
        "created_at" => "2030-01-01T00:00:00Z",
        "updated_at" => "2030-01-01T00:00:00Z",
        "public_url" => nil,
        "next_recommended_action" => "none",
        "next_poll_at" => nil,
        "approval_required" => false,
        "chain_id" => nil,
        "transaction_hash" => nil,
        "error_code" => nil
      }
    }

    report
    |> apply_outcome(outcome)
    |> rekey()
  end

  def rekey(report) do
    report_id = UpliftReport.expected_report_id(report)
    package_digest = get_in(report, ["reproduction_package", "digest"])

    action_receipt =
      report
      |> Map.fetch!("action_receipt")
      |> Map.merge(%{
        "action_id" => UpliftReport.expected_action_id(report_id, package_digest),
        "resource_id" => report_id,
        "idempotency_key" =>
          UpliftReport.expected_idempotency_key(get_in(report, ["comparison", "receipt_digests"]))
      })

    Map.merge(report, %{"report_id" => report_id, "action_receipt" => action_receipt})
  end

  defp apply_outcome(report, "positive"), do: report

  defp apply_outcome(report, "null"),
    do: update_scores(report, "null", 500, 500, 0, 0)

  defp apply_outcome(report, "negative"),
    do: update_scores(report, "negative", 500, 300, -200, -400)

  defp apply_outcome(report, "inconclusive"),
    do: update_scores(report, "inconclusive", 500, 505, 5, 10)

  defp apply_outcome(report, "invalid") do
    report
    |> update_scores("invalid", nil, nil, nil, nil)
    |> update_in(
      ["scored_evaluation", "task_scores", Access.at(0)],
      &Map.merge(&1, %{
        "baseline_status" => "failed",
        "candidate_status" => "failed"
      })
    )
    |> Map.put(
      "decision_sentence",
      "This single-run comparison was invalid because the receipt-backed held-out result was not valid."
    )
  end

  defp update_scores(report, outcome, baseline, candidate, delta, relative_change) do
    task_score =
      report
      |> get_in(["scored_evaluation", "task_scores", Access.at(0)])
      |> Map.merge(%{
        "baseline_score_millis" => baseline,
        "candidate_score_millis" => candidate,
        "delta_millis" => delta,
        "classification" => if(is_integer(delta) and delta > 0, do: "improved", else: "unchanged")
      })

    family_difference =
      report
      |> get_in(["scored_evaluation", "family_differences", Access.at(0)])
      |> Map.merge(%{
        "baseline_mean_millis" => baseline,
        "candidate_mean_millis" => candidate,
        "delta_millis" => delta
      })

    scored =
      report["scored_evaluation"]
      |> Map.merge(%{
        "score_distributions" => %{
          "baseline" => distribution(if(is_integer(baseline), do: [baseline], else: [])),
          "candidate" => distribution(if(is_integer(candidate), do: [candidate], else: []))
        },
        "task_scores" => [task_score],
        "family_differences" => [family_difference],
        "baseline_mean_millis" => baseline,
        "candidate_mean_millis" => candidate,
        "delta_millis" => delta,
        "claim_eligible" => is_integer(delta)
      })

    report
    |> Map.put("scored_evaluation", scored)
    |> Map.put("outcome", outcome)
    |> Map.put("final_capability_level", %{
      "scale" => "score_millis",
      "baseline" => baseline,
      "candidate" => candidate
    })
    |> Map.put("measured_change", %{
      "absolute_delta_millis" => delta,
      "relative_error_reduction_millis" => relative_change
    })
    |> Map.put("uncertainty", %{
      "treatment" => "declared-point-delta",
      "point_delta_millis" => delta,
      "confidence_interval" => nil
    })
    |> Map.put("decision_sentence", decision_sentence(outcome, candidate))
  end

  defp decision_sentence("null", candidate),
    do:
      "This skill showed no measurable change on the held-out result, ending at #{div(candidate, 10)}%, with no severe regressions."

  defp decision_sentence("negative", candidate),
    do:
      "This skill hurt held-out performance by 20 percentage points, ending at #{div(candidate, 10)}%, with no severe regressions."

  defp decision_sentence("inconclusive", _candidate),
    do:
      "This single-run comparison could not tell whether the skill produced a measured improvement on the held-out result."

  defp decision_sentence("invalid", _candidate),
    do:
      "This single-run comparison was invalid because the receipt-backed held-out result was not valid."

  defp arm(id, capsule_id) do
    %{
      "arm_id" => id,
      "role" => id,
      "model" => %{
        "provider" => "fixture",
        "identifier" => "model-1",
        "version" => "1",
        "behavioral_fingerprint" => nil,
        "mutability" => "locked"
      },
      "capsule_id" => capsule_id,
      "gating" => true,
      "evidence_only" => false
    }
  end

  defp binding(task_id, provenance, baseline_digest, candidate_digest) do
    %{
      "task_id" => task_id,
      "provenance" => provenance,
      "baseline_run_digest" => String.duplicate(baseline_digest, 64),
      "candidate_run_digest" => String.duplicate(candidate_digest, 64)
    }
  end

  defp evaluation(provenance, task_id, baseline, candidate, contamination, claim_eligible) do
    delta = candidate - baseline

    %{
      "provenance" => provenance,
      "possible_contamination" => contamination,
      "score_distributions" => %{
        "baseline" => distribution([baseline]),
        "candidate" => distribution([candidate])
      },
      "task_scores" => [
        %{
          "task_id" => task_id,
          "family_id" => "family-1",
          "provenance" => provenance,
          "baseline_status" => "completed",
          "candidate_status" => "completed",
          "baseline_score_millis" => baseline,
          "candidate_score_millis" => candidate,
          "delta_millis" => delta,
          "classification" => if(delta > 0, do: "improved", else: "unchanged"),
          "regression_severity" => "non-severe",
          "possible_contamination" => contamination
        }
      ],
      "family_differences" => [
        %{
          "family_id" => "family-1",
          "provenance" => provenance,
          "task_count" => 1,
          "baseline_mean_millis" => baseline,
          "candidate_mean_millis" => candidate,
          "delta_millis" => delta,
          "possible_contamination" => contamination
        }
      ],
      "task_count" => 1,
      "claim_eligible" => claim_eligible,
      "baseline_mean_millis" => baseline,
      "candidate_mean_millis" => candidate,
      "delta_millis" => delta
    }
  end

  defp distribution(values) do
    %{
      "values" => values,
      "count" => length(values),
      "total" => Enum.sum(values),
      "minimum" => if(values == [], do: nil, else: Enum.min(values)),
      "maximum" => if(values == [], do: nil, else: Enum.max(values)),
      "mean" => if(values == [], do: nil, else: div(Enum.sum(values), length(values)))
    }
  end
end
