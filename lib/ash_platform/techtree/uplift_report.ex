defmodule AshPlatform.Techtree.UpliftReport do
  @moduledoc """
  Strict decoder and deterministic human projection of the canonical UpliftReport payload.

  This module never stores or rewrites a report. The fetched JSON remains the
  only report shape; the projection is a short-lived rendering model.
  """

  @top_level_keys ~w(
    schema_version report_id comparison arms receipt_bindings decision_rule
    scored_evaluation calibration outcome final_capability_level measured_change
    regressions uncertainty cost_latency disclosures limitations freshness
    evidence_class reproduction_status reproduction_package_status
    decision_sentence reproduction_package action_receipt
  )

  @outcome_labels %{
    "positive" => "Helped",
    "null" => "No measurable change",
    "negative" => "Hurt performance",
    "inconclusive" => "Could not tell",
    "invalid" => "Run invalid"
  }

  @outcomes Map.keys(@outcome_labels)
  @provenances ["held_out", "public_reference"]
  @possible_contamination "possible-contamination"
  @evidence_class "single_run"
  @reproduction_status "not_run"
  @reproduction_package_statuses ["available", "absent"]
  @sha256_pattern ~r/\A[0-9a-f]{64}\z/
  @max_record_integer 1_000_000_000

  @spec decode(term()) :: {:ok, map()} | :not_uplift_report
  def decode(report) when is_map(report) do
    :ok = validate_report!(report)
    {:ok, report}
  rescue
    _error -> :not_uplift_report
  catch
    :invalid -> :not_uplift_report
  end

  def decode(_report), do: :not_uplift_report

  @spec project(term()) :: {:ok, map()} | :not_uplift_report
  def project(report) do
    with {:ok, canonical} <- decode(report) do
      {:ok, project_canonical(canonical)}
    end
  end

  @spec project_json(binary()) :: {:ok, map()} | :not_uplift_report
  def project_json(bytes) when is_binary(bytes) do
    case Jason.decode(bytes, objects: :ordered_objects) do
      {:ok, value} ->
        case strict_json_value(value) do
          {:ok, report} -> project(report)
          :not_uplift_report -> :not_uplift_report
        end

      _result ->
        :not_uplift_report
    end
  end

  def project_json(_bytes), do: :not_uplift_report

  @spec not_recognized() :: %{status: :not_recognized}
  def not_recognized, do: %{status: :not_recognized}

  @spec expected_report_id(map()) :: String.t()
  def expected_report_id(report) when is_map(report) do
    report
    |> Map.drop(["report_id", "action_receipt"])
    |> content_id("uplift-report")
  end

  @spec expected_action_id(String.t(), String.t() | nil) :: String.t()
  def expected_action_id(report_id, package_digest) when is_binary(report_id) do
    content_id(%{"report_id" => report_id, "package_digest" => package_digest}, "action")
  end

  @spec expected_idempotency_key([String.t()]) :: String.t()
  def expected_idempotency_key(receipt_digests) when is_list(receipt_digests) do
    content_id(%{"receipt_digests" => receipt_digests}, "uplift-action")
  end

  defp validate_report!(report) do
    require_exact_keys!(report, @top_level_keys)
    expect!(Map.get(report, "schema_version") === 1)

    report_id = require_identifier!(Map.fetch!(report, "report_id"))
    comparison = validate_comparison!(Map.fetch!(report, "comparison"))
    validate_arms!(Map.fetch!(report, "arms"))
    receipt_bindings = validate_receipt_bindings!(Map.fetch!(report, "receipt_bindings"))
    decision_rule = validate_decision_rule!(Map.fetch!(report, "decision_rule"))

    scored_evaluation =
      validate_evaluation!(
        Map.fetch!(report, "scored_evaluation"),
        "held_out",
        decision_rule["minimum_valid_task_count"]
      )

    calibration =
      case Map.fetch!(report, "calibration") do
        nil ->
          nil

        value ->
          validate_evaluation!(
            value,
            "public_reference",
            decision_rule["minimum_valid_task_count"]
          )
      end

    outcome = require_enum!(Map.fetch!(report, "outcome"), @outcomes)

    final_capability =
      validate_final_capability!(Map.fetch!(report, "final_capability_level"), scored_evaluation)

    measured_change =
      validate_measured_change!(
        Map.fetch!(report, "measured_change"),
        scored_evaluation,
        decision_rule
      )

    validate_uncertainty!(Map.fetch!(report, "uncertainty"), scored_evaluation)
    regressions = validate_regressions!(Map.fetch!(report, "regressions"))
    validate_cost_latency!(Map.fetch!(report, "cost_latency"))
    require_map!(Map.fetch!(report, "disclosures"))
    validate_limitations!(Map.fetch!(report, "limitations"))
    validate_freshness!(Map.fetch!(report, "freshness"))
    expect!(outcome == derived_outcome(decision_rule, scored_evaluation, calibration))

    expect!(Map.fetch!(report, "evidence_class") == @evidence_class)
    expect!(Map.fetch!(report, "reproduction_status") == @reproduction_status)

    package_digest =
      validate_reproduction_package!(
        Map.fetch!(report, "reproduction_package_status"),
        Map.fetch!(report, "reproduction_package")
      )

    sentence = require_string!(Map.fetch!(report, "decision_sentence"))
    expect!(sentence == decision_sentence(outcome, scored_evaluation, regressions))

    validate_provenance_bindings!(receipt_bindings, scored_evaluation, calibration)

    validate_action_receipt!(
      Map.fetch!(report, "action_receipt"),
      report_id,
      package_digest,
      comparison
    )

    expect!(report_id == expected_report_id(report))
    expect!(final_capability["candidate"] == scored_evaluation.candidate_mean)
    expect!(measured_change["absolute_delta_millis"] == scored_evaluation.delta)

    :ok
  end

  defp validate_comparison!(value) do
    comparison = require_exact_keys!(value, ~w(receipt_digests protocol_id family_id))
    digests = require_list!(Map.fetch!(comparison, "receipt_digests"))
    expect!(length(digests) == 2)
    Enum.each(digests, &require_sha256!/1)
    require_identifier!(Map.fetch!(comparison, "protocol_id"))
    require_identifier!(Map.fetch!(comparison, "family_id"))
    comparison
  end

  defp validate_arms!(value) do
    arms = require_list!(value)

    normalized =
      Enum.map(arms, fn arm ->
        arm = require_exact_keys!(arm, ~w(arm_id role model capsule_id gating evidence_only))
        require_identifier!(Map.fetch!(arm, "arm_id"))
        require_identifier!(Map.fetch!(arm, "role"))
        validate_model_identity!(Map.fetch!(arm, "model"))
        require_identifier!(Map.fetch!(arm, "capsule_id"))
        gating = require_boolean!(Map.fetch!(arm, "gating"))
        evidence_only = require_boolean!(Map.fetch!(arm, "evidence_only"))
        expect!(not (gating and evidence_only))
        arm
      end)

    arm_ids = Enum.map(normalized, &Map.fetch!(&1, "arm_id"))
    expect!(length(Enum.uniq(arm_ids)) == length(arm_ids))
    expect!(Enum.all?(~w(baseline candidate), &(&1 in arm_ids)))
    :ok
  end

  defp validate_model_identity!(value) do
    model =
      require_exact_keys!(
        value,
        ~w(provider identifier version behavioral_fingerprint mutability)
      )

    require_identifier!(Map.fetch!(model, "provider"))
    require_identifier!(Map.fetch!(model, "identifier"))
    require_identifier!(Map.fetch!(model, "version"))
    require_nullable_string!(Map.fetch!(model, "behavioral_fingerprint"))
    require_identifier!(Map.fetch!(model, "mutability"))
    :ok
  end

  defp validate_receipt_bindings!(value) do
    bindings =
      Enum.map(require_list!(value), fn binding ->
        binding =
          require_exact_keys!(
            binding,
            ~w(task_id provenance baseline_run_digest candidate_run_digest)
          )

        require_identifier!(Map.fetch!(binding, "task_id"))
        require_enum!(Map.fetch!(binding, "provenance"), @provenances)
        require_sha256!(Map.fetch!(binding, "baseline_run_digest"))
        require_sha256!(Map.fetch!(binding, "candidate_run_digest"))
        binding
      end)

    task_ids = Enum.map(bindings, &Map.fetch!(&1, "task_id"))
    expect!(length(Enum.uniq(task_ids)) == length(task_ids))
    bindings
  end

  defp validate_decision_rule!(value) do
    rule =
      require_exact_keys!(
        value,
        ~w(primary_metric minimum_valid_task_count positive_threshold_millis negative_threshold_millis null_band_millis severe_regression_rule inconclusive_conditions invalid_conditions)
      )

    require_identifier!(Map.fetch!(rule, "primary_metric"))
    expect!(Map.fetch!(rule, "primary_metric") == "score_millis")
    require_integer!(Map.fetch!(rule, "minimum_valid_task_count"), 1)
    positive = require_integer!(Map.fetch!(rule, "positive_threshold_millis"), 0)

    negative =
      require_integer!(Map.fetch!(rule, "negative_threshold_millis"), -@max_record_integer)

    null_band = require_integer!(Map.fetch!(rule, "null_band_millis"), 0)
    expect!(positive > null_band and negative < -null_band)
    validate_severe_regression_rule!(Map.fetch!(rule, "severe_regression_rule"))

    validate_conditions!(Map.fetch!(rule, "inconclusive_conditions"), [
      "valid_task_count_below_minimum",
      "delta_between_thresholds"
    ])

    validate_conditions!(Map.fetch!(rule, "invalid_conditions"), [
      "any_arm_not_completed",
      "missing_score"
    ])

    rule
  end

  defp validate_severe_regression_rule!(value) do
    rule = require_exact_keys!(value, ~w(kind threshold_millis))
    expect!(Map.fetch!(rule, "kind") == "delta_at_or_below")
    require_integer!(Map.fetch!(rule, "threshold_millis"), 1)
    :ok
  end

  defp validate_conditions!(value, allowed) do
    conditions = Enum.map(require_list!(value), &require_string!/1)
    expect!(length(Enum.uniq(conditions)) == length(conditions))
    expect!(Enum.all?(conditions, &(&1 in allowed)))
    :ok
  end

  defp validate_evaluation!(value, expected_provenance, minimum_valid_task_count) do
    evaluation =
      require_exact_keys!(
        value,
        ~w(provenance possible_contamination score_distributions task_scores family_differences task_count claim_eligible baseline_mean_millis candidate_mean_millis delta_millis)
      )

    expect!(Map.fetch!(evaluation, "provenance") == expected_provenance)
    validate_contamination!(expected_provenance, Map.fetch!(evaluation, "possible_contamination"))

    distributions =
      require_exact_keys!(Map.fetch!(evaluation, "score_distributions"), ~w(baseline candidate))

    baseline_distribution = validate_distribution!(Map.fetch!(distributions, "baseline"))
    candidate_distribution = validate_distribution!(Map.fetch!(distributions, "candidate"))

    scores =
      Enum.map(require_list!(Map.fetch!(evaluation, "task_scores")), fn score ->
        validate_task_score!(score, expected_provenance)
      end)

    families =
      Enum.map(require_list!(Map.fetch!(evaluation, "family_differences")), fn family ->
        validate_family_difference!(family, expected_provenance)
      end)

    task_ids = Enum.map(scores, & &1.task_id)
    expect!(length(Enum.uniq(task_ids)) == length(task_ids))
    task_count = require_integer!(Map.fetch!(evaluation, "task_count"), 0)
    expect!(task_count == length(scores))

    valid_scores =
      Enum.filter(scores, fn score ->
        not is_nil(score.baseline_score) and not is_nil(score.candidate_score) and
          not is_nil(score.delta)
      end)

    expected_baseline_values = Enum.map(valid_scores, & &1.baseline_score)
    expected_candidate_values = Enum.map(valid_scores, & &1.candidate_score)
    expect!(baseline_distribution.values == expected_baseline_values)
    expect!(candidate_distribution.values == expected_candidate_values)

    baseline_mean = baseline_distribution.mean
    candidate_mean = candidate_distribution.mean

    delta =
      if is_integer(baseline_mean) and is_integer(candidate_mean),
        do: candidate_mean - baseline_mean

    expect!(Map.fetch!(evaluation, "baseline_mean_millis") == baseline_mean)
    expect!(Map.fetch!(evaluation, "candidate_mean_millis") == candidate_mean)
    expect!(Map.fetch!(evaluation, "delta_millis") == delta)

    claim_eligible = require_boolean!(Map.fetch!(evaluation, "claim_eligible"))

    expected_claim =
      expected_provenance == "held_out" and valid_scores != [] and
        length(valid_scores) == length(scores) and
        length(valid_scores) >= minimum_valid_task_count

    expect!(claim_eligible == expected_claim)
    expect!(not (expected_provenance == "public_reference" and claim_eligible))
    expect!(Enum.sum(Enum.map(families, & &1.task_count)) == task_count)

    expect!(
      MapSet.new(Enum.map(families, & &1.family_id)) ==
        MapSet.new(Enum.map(scores, & &1.family_id))
    )

    %{
      provenance: expected_provenance,
      task_ids: task_ids,
      baseline_mean: baseline_mean,
      candidate_mean: candidate_mean,
      delta: delta,
      scores: scores
    }
  end

  defp validate_distribution!(value) do
    distribution = require_exact_keys!(value, ~w(values count total minimum maximum mean))

    values =
      Enum.map(
        require_list!(Map.fetch!(distribution, "values")),
        &require_integer!(&1, -@max_record_integer)
      )

    count = require_integer!(Map.fetch!(distribution, "count"), 0)
    total = require_integer!(Map.fetch!(distribution, "total"), -@max_record_integer)
    minimum = require_nullable_integer!(Map.fetch!(distribution, "minimum"))
    maximum = require_nullable_integer!(Map.fetch!(distribution, "maximum"))
    mean = require_nullable_integer!(Map.fetch!(distribution, "mean"))

    expected = %{
      values: values,
      count: length(values),
      total: Enum.sum(values),
      minimum: if(values == [], do: nil, else: Enum.min(values)),
      maximum: if(values == [], do: nil, else: Enum.max(values)),
      mean: if(values == [], do: nil, else: div(Enum.sum(values), length(values)))
    }

    expect!(
      %{
        values: values,
        count: count,
        total: total,
        minimum: minimum,
        maximum: maximum,
        mean: mean
      } == expected
    )

    expected
  end

  defp validate_task_score!(value, expected_provenance) do
    score =
      require_exact_keys!(
        value,
        ~w(task_id family_id provenance baseline_status candidate_status baseline_score_millis candidate_score_millis delta_millis classification regression_severity possible_contamination)
      )

    require_identifier!(Map.fetch!(score, "task_id"))
    require_identifier!(Map.fetch!(score, "family_id"))
    expect!(Map.fetch!(score, "provenance") == expected_provenance)
    validate_contamination!(expected_provenance, Map.fetch!(score, "possible_contamination"))
    require_string!(Map.fetch!(score, "baseline_status"))
    require_string!(Map.fetch!(score, "candidate_status"))
    baseline_score = require_nullable_integer!(Map.fetch!(score, "baseline_score_millis"))
    candidate_score = require_nullable_integer!(Map.fetch!(score, "candidate_score_millis"))
    delta = require_nullable_integer!(Map.fetch!(score, "delta_millis"))
    require_string!(Map.fetch!(score, "classification"))
    require_string!(Map.fetch!(score, "regression_severity"))

    expected_delta =
      if is_integer(baseline_score) and is_integer(candidate_score),
        do: candidate_score - baseline_score,
        else: nil

    expect!(delta == expected_delta)

    %{
      task_id: Map.fetch!(score, "task_id"),
      family_id: Map.fetch!(score, "family_id"),
      baseline_status: Map.fetch!(score, "baseline_status"),
      candidate_status: Map.fetch!(score, "candidate_status"),
      baseline_score: baseline_score,
      candidate_score: candidate_score,
      delta: delta
    }
  end

  defp validate_family_difference!(value, expected_provenance) do
    family =
      require_exact_keys!(
        value,
        ~w(family_id provenance task_count baseline_mean_millis candidate_mean_millis delta_millis possible_contamination)
      )

    require_identifier!(Map.fetch!(family, "family_id"))
    expect!(Map.fetch!(family, "provenance") == expected_provenance)
    validate_contamination!(expected_provenance, Map.fetch!(family, "possible_contamination"))
    require_integer!(Map.fetch!(family, "task_count"), 0)
    baseline_mean = require_nullable_integer!(Map.fetch!(family, "baseline_mean_millis"))
    candidate_mean = require_nullable_integer!(Map.fetch!(family, "candidate_mean_millis"))
    delta = require_nullable_integer!(Map.fetch!(family, "delta_millis"))

    expect!(
      delta ==
        if(is_integer(baseline_mean) and is_integer(candidate_mean),
          do: candidate_mean - baseline_mean,
          else: nil
        )
    )

    family
    |> Map.put(:family_id, Map.fetch!(family, "family_id"))
    |> Map.put(:task_count, Map.fetch!(family, "task_count"))
  end

  defp validate_contamination!("public_reference", value),
    do: expect!(value == @possible_contamination)

  defp validate_contamination!("held_out", value), do: expect!(is_nil(value))

  defp derived_outcome(decision_rule, evaluation, calibration) do
    all_scores = evaluation.scores ++ if(calibration, do: calibration.scores, else: [])

    cond do
      invalid_outcome?(decision_rule, all_scores) ->
        "invalid"

      valid_count_below_minimum?(decision_rule, evaluation) ->
        if "valid_task_count_below_minimum" in decision_rule["inconclusive_conditions"],
          do: "inconclusive",
          else: "invalid"

      is_nil(evaluation.delta) ->
        "inconclusive"

      true ->
        scored_outcome(decision_rule, evaluation.delta)
    end
  end

  defp invalid_outcome?(decision_rule, scores) do
    any_arm_not_completed? =
      Enum.any?(scores, fn score ->
        score.baseline_status != "completed" or score.candidate_status != "completed"
      end)

    missing_score? = Enum.any?(scores, fn score -> is_nil(score.delta) end)

    ("any_arm_not_completed" in decision_rule["invalid_conditions"] and any_arm_not_completed?) or
      ("missing_score" in decision_rule["invalid_conditions"] and missing_score?)
  end

  defp valid_count_below_minimum?(decision_rule, evaluation) do
    Enum.count(evaluation.scores, &is_integer(&1.delta)) <
      decision_rule["minimum_valid_task_count"]
  end

  defp scored_outcome(decision_rule, delta) do
    cond do
      delta >= decision_rule["positive_threshold_millis"] ->
        "positive"

      delta <= decision_rule["negative_threshold_millis"] ->
        "negative"

      abs(delta) <= decision_rule["null_band_millis"] ->
        "null"

      "delta_between_thresholds" in decision_rule["inconclusive_conditions"] ->
        "inconclusive"

      true ->
        "invalid"
    end
  end

  defp validate_final_capability!(value, evaluation) do
    capability = require_exact_keys!(value, ~w(scale baseline candidate))
    expect!(Map.fetch!(capability, "scale") == "score_millis")
    baseline = require_nullable_integer!(Map.fetch!(capability, "baseline"))
    candidate = require_nullable_integer!(Map.fetch!(capability, "candidate"))
    expect!({baseline, candidate} == {evaluation.baseline_mean, evaluation.candidate_mean})
    capability
  end

  defp validate_measured_change!(value, evaluation, decision_rule) do
    change = require_exact_keys!(value, ~w(absolute_delta_millis relative_error_reduction_millis))
    absolute = require_nullable_integer!(Map.fetch!(change, "absolute_delta_millis"))
    relative = require_nullable_integer!(Map.fetch!(change, "relative_error_reduction_millis"))
    expect!(absolute == evaluation.delta)
    expect!(relative == relative_error_reduction(decision_rule, evaluation))
    change
  end

  defp relative_error_reduction(_decision_rule, evaluation) do
    with baseline when is_integer(baseline) <- evaluation.baseline_mean,
         candidate when is_integer(candidate) <- evaluation.candidate_mean,
         baseline_error when baseline_error > 0 <- 1_000 - baseline do
      round((baseline_error - (1_000 - candidate)) * 1_000 / baseline_error)
    else
      _result -> nil
    end
  end

  defp validate_uncertainty!(value, evaluation) do
    uncertainty = require_exact_keys!(value, ~w(treatment point_delta_millis confidence_interval))
    expect!(Map.fetch!(uncertainty, "treatment") == "declared-point-delta")
    expect!(Map.fetch!(uncertainty, "point_delta_millis") == evaluation.delta)
    expect!(is_nil(Map.fetch!(uncertainty, "confidence_interval")))
    :ok
  end

  defp validate_regressions!(value) do
    regressions = require_exact_keys!(value, ~w(severe non_severe severe_count non_severe_count))
    severe = Enum.map(require_list!(Map.fetch!(regressions, "severe")), &require_identifier!/1)

    non_severe =
      Enum.map(require_list!(Map.fetch!(regressions, "non_severe")), &require_identifier!/1)

    expect!(Map.fetch!(regressions, "severe_count") == length(severe))
    expect!(Map.fetch!(regressions, "non_severe_count") == length(non_severe))
    %{severe: severe, non_severe: non_severe}
  end

  defp validate_cost_latency!(value) do
    cost_latency = require_exact_keys!(value, ~w(baseline candidate))

    for arm <- ~w(baseline candidate) do
      metrics =
        require_exact_keys!(Map.fetch!(cost_latency, arm), ~w(cost_usd_cents wall_time_ms))

      validate_distribution!(Map.fetch!(metrics, "cost_usd_cents"))
      validate_distribution!(Map.fetch!(metrics, "wall_time_ms"))
    end

    :ok
  end

  defp validate_limitations!(value) do
    Enum.each(require_list!(value), &require_string!/1)
    :ok
  end

  defp validate_freshness!(value) do
    freshness = require_exact_keys!(value, ~w(status as_of invalidation_triggers))
    require_string!(Map.fetch!(freshness, "status"))
    require_nullable_string!(Map.fetch!(freshness, "as_of"))
    Enum.each(require_list!(Map.fetch!(freshness, "invalidation_triggers")), &require_string!/1)
    :ok
  end

  defp validate_reproduction_package!(status, package) do
    status = require_enum!(status, @reproduction_package_statuses)

    case status do
      "available" ->
        package = require_exact_keys!(package, ~w(algorithm digest))
        expect!(Map.fetch!(package, "algorithm") == "sha256")
        require_sha256!(Map.fetch!(package, "digest"))
        Map.fetch!(package, "digest")

      "absent" ->
        expect!(is_nil(package))
        nil
    end
  end

  defp validate_provenance_bindings!(bindings, scored_evaluation, calibration) do
    held_out_ids =
      bindings
      |> Enum.filter(&(Map.fetch!(&1, "provenance") == "held_out"))
      |> Enum.map(&Map.fetch!(&1, "task_id"))
      |> MapSet.new()

    reference_ids =
      bindings
      |> Enum.filter(&(Map.fetch!(&1, "provenance") == "public_reference"))
      |> Enum.map(&Map.fetch!(&1, "task_id"))
      |> MapSet.new()

    expect!(MapSet.new(scored_evaluation.task_ids) == held_out_ids)
    expect!(reference_ids != MapSet.new() == not is_nil(calibration))

    if calibration do
      expect!(MapSet.new(calibration.task_ids) == reference_ids)
    end

    :ok
  end

  defp validate_action_receipt!(value, report_id, package_digest, comparison) do
    receipt =
      require_exact_keys!(
        value,
        ~w(action_id capability_id action_kind resource_type resource_id status idempotency_key created_at updated_at public_url next_recommended_action next_poll_at approval_required chain_id transaction_hash error_code)
      )

    require_identifier!(Map.fetch!(receipt, "action_id"))
    require_identifier!(Map.fetch!(receipt, "capability_id"))
    require_identifier!(Map.fetch!(receipt, "action_kind"))
    require_identifier!(Map.fetch!(receipt, "resource_type"))
    expect!(Map.fetch!(receipt, "resource_id") == report_id)
    require_identifier!(Map.fetch!(receipt, "status"))
    require_identifier!(Map.fetch!(receipt, "idempotency_key"))
    require_nullable_string!(Map.fetch!(receipt, "created_at"))
    require_nullable_string!(Map.fetch!(receipt, "updated_at"))
    require_nullable_string!(Map.fetch!(receipt, "public_url"))
    require_string!(Map.fetch!(receipt, "next_recommended_action"))
    require_nullable_string!(Map.fetch!(receipt, "next_poll_at"))
    require_boolean!(Map.fetch!(receipt, "approval_required"))

    case Map.fetch!(receipt, "chain_id") do
      nil -> :ok
      chain_id -> require_integer!(chain_id, 0)
    end

    require_nullable_string!(Map.fetch!(receipt, "transaction_hash"))
    require_nullable_string!(Map.fetch!(receipt, "error_code"))

    expect!(Map.fetch!(receipt, "action_id") == expected_action_id(report_id, package_digest))

    expect!(
      Map.fetch!(receipt, "idempotency_key") ==
        expected_idempotency_key(Map.fetch!(comparison, "receipt_digests"))
    )

    :ok
  end

  defp decision_sentence("positive", evaluation, regressions) do
    "This skill improved held-out performance by #{percentage_phrase(evaluation.delta)}, ending at #{percentage(evaluation.candidate_mean)}%, with #{regression_sentence(regressions)}."
  end

  defp decision_sentence("negative", evaluation, regressions) do
    "This skill hurt held-out performance by #{percentage_phrase(evaluation.delta)}, ending at #{percentage(evaluation.candidate_mean)}%, with #{regression_sentence(regressions)}."
  end

  defp decision_sentence("null", evaluation, regressions) do
    "This skill showed no measurable change on the held-out result, ending at #{percentage(evaluation.candidate_mean)}%, with #{regression_sentence(regressions)}."
  end

  defp decision_sentence("invalid", _evaluation, _regressions),
    do:
      "This single-run comparison was invalid because the receipt-backed held-out result was not valid."

  defp decision_sentence("inconclusive", _evaluation, _regressions),
    do:
      "This single-run comparison could not tell whether the skill produced a measured improvement on the held-out result."

  defp percentage(nil), do: "unavailable"

  defp percentage(value) when is_integer(value) do
    magnitude = abs(value)
    whole = div(magnitude, 10)
    remainder = rem(magnitude, 10)
    if remainder == 0, do: Integer.to_string(whole), else: "#{whole}.#{remainder}"
  end

  defp percentage_phrase(nil), do: "unavailable percentage points"

  defp percentage_phrase(value) when is_integer(value) do
    rendered = percentage(abs(value))
    suffix = if abs(value) == 10, do: "percentage point", else: "percentage points"
    "#{rendered} #{suffix}"
  end

  defp regression_sentence(%{severe: []}), do: "no severe regressions"

  defp regression_sentence(%{severe: severe}) do
    count = length(severe)
    if count == 1, do: "1 severe regression", else: "#{count} severe regressions"
  end

  defp project_canonical(report) do
    calibration =
      case Map.get(report, "calibration") do
        nil ->
          nil

        value ->
          Map.put(
            value,
            "warning",
            "Possible contamination: public-reference scores do not carry the uplift claim."
          )
      end

    %{
      status: :recognized,
      outcome: %{value: report["outcome"], label: Map.fetch!(@outcome_labels, report["outcome"])},
      final_capability: report["final_capability_level"],
      measured_change: report["measured_change"],
      regressions: report["regressions"],
      cost_latency: report["cost_latency"],
      evidence: %{
        class: "Single run",
        reproduction_status: "Reproduction not run",
        reproduction_package:
          if(report["reproduction_package_status"] == "available",
            do: "Reproduction package included",
            else: "Reproduction package not available"
          )
      },
      scored_evaluation: report["scored_evaluation"],
      calibration: calibration,
      inspect_evidence:
        Map.take(report, [
          "schema_version",
          "report_id",
          "comparison",
          "receipt_bindings",
          "decision_rule",
          "evidence_class",
          "reproduction_status",
          "reproduction_package_status",
          "arms",
          "uncertainty",
          "disclosures",
          "limitations",
          "freshness",
          "decision_sentence",
          "reproduction_package",
          "action_receipt"
        ])
        |> Enum.sort_by(&elem(&1, 0))
        |> Map.new()
    }
  end

  defp strict_json_value(%Jason.OrderedObject{values: pairs}) do
    keys = Enum.map(pairs, &elem(&1, 0))

    if length(Enum.uniq(keys)) != length(keys) do
      :not_uplift_report
    else
      strict_json_pairs(pairs)
    end
  end

  defp strict_json_value(value) when is_list(value) do
    case Enum.reduce_while(value, [], &strict_json_list_item/2) do
      :not_uplift_report -> :not_uplift_report
      values -> {:ok, Enum.reverse(values)}
    end
  end

  defp strict_json_value(value), do: {:ok, value}

  defp strict_json_pairs(pairs) do
    case Enum.reduce_while(pairs, [], &strict_json_pair/2) do
      :not_uplift_report -> :not_uplift_report
      values -> {:ok, Map.new(values)}
    end
  end

  defp strict_json_list_item(item, values) do
    case strict_json_value(item) do
      {:ok, item} -> {:cont, [item | values]}
      :not_uplift_report -> {:halt, :not_uplift_report}
    end
  end

  defp strict_json_pair({key, value}, values) do
    case strict_json_value(value) do
      {:ok, value} -> {:cont, [{key, value} | values]}
      :not_uplift_report -> {:halt, :not_uplift_report}
    end
  end

  defp require_exact_keys!(value, keys) when is_map(value) do
    expect!(MapSet.new(Map.keys(value)) == MapSet.new(keys))
    value
  end

  defp require_exact_keys!(_value, _keys), do: invalid!()

  defp require_map!(value) when is_map(value), do: value
  defp require_map!(_value), do: invalid!()

  defp require_list!(value) when is_list(value), do: value
  defp require_list!(_value), do: invalid!()

  defp require_string!(value) when is_binary(value) do
    expect!(value != "")
    expect!(String.printable?(value))
    value
  end

  defp require_string!(_value), do: invalid!()

  defp require_identifier!(value) do
    value = require_string!(value)
    expect!(String.trim(value) == value)
    expect!(String.length(value) <= 256)
    value
  end

  defp require_nullable_string!(nil), do: nil
  defp require_nullable_string!(value), do: require_string!(value)

  defp require_boolean!(value) when is_boolean(value), do: value
  defp require_boolean!(_value), do: invalid!()

  defp require_integer!(value, minimum) when is_integer(value) do
    expect!(value >= minimum and value <= @max_record_integer)
    value
  end

  defp require_integer!(_value, _minimum), do: invalid!()

  defp require_nullable_integer!(nil), do: nil
  defp require_nullable_integer!(value), do: require_integer!(value, -@max_record_integer)

  defp require_sha256!(value) do
    expect!(is_binary(value) and Regex.match?(@sha256_pattern, value))
    value
  end

  defp require_enum!(value, allowed) do
    value = require_string!(value)
    expect!(value in allowed)
    value
  end

  defp expect!(true), do: :ok
  defp expect!(_value), do: invalid!()

  defp invalid!, do: throw(:invalid)

  defp content_id(value, prefix) do
    encoded =
      value
      |> canonical_json_value()
      |> Jason.encode_to_iodata!(maps: :strict)
      |> IO.iodata_to_binary()

    digest = :crypto.hash(:sha256, encoded <> "\n") |> Base.encode16(case: :lower)
    prefix <> "-" <> binary_part(digest, 0, 24)
  end

  defp canonical_json_value(value) when is_map(value) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, item} -> {key, canonical_json_value(item)} end)
    |> Jason.OrderedObject.new()
  end

  defp canonical_json_value(value) when is_list(value),
    do: Enum.map(value, &canonical_json_value/1)

  defp canonical_json_value(value), do: value
end
