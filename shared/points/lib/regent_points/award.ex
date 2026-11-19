defmodule RegentPoints.Award do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Rules, Store}

  @reference [:rule_id, :source_app, :source_kind, :source_event_key]

  @impl true
  def run(%{arguments: %{event_id: id}}, _, _) do
    case Store.event(id) do
      nil ->
        {:error, "Unknown points event"}

      %{processing_status: status} = event when status != :pending ->
        {:ok, %{id: event.id, status: status}}

      %{account_id: account} = event ->
        Ash.transact(Account, fn ->
          Store.lock_account(account)

          # An event offered again for another account meanwhile is that offer's
          # own run's to award, under that account's lock.
          case Store.event(event.id) do
            %{processing_status: :pending, account_id: ^account} = event -> check(event)
            event -> %{id: event.id, status: event.processing_status}
          end
        end)
    end
  end

  # The source is asked again under the account's lock, in the transaction that
  # writes the award, so a source refused since intake earns nothing. Its answer only
  # accepts or refuses: the facts and rule saved at intake decide the award, and a yes
  # counts only for the account saved at intake. An answer it cannot give rolls the
  # transaction back, and Oban retries.
  defp check(%{account_id: account} = event) do
    reference = Map.new(@reference, &{to_string(&1), Map.fetch!(event, &1)})

    case Rules.adapter(event.rule_id).verify(reference) do
      {:ok, %{account_id: ^account}} -> award(event)
      {:ok, _facts} -> refuse(event, reference, :account_changed)
      {:error, reason} when is_atom(reason) -> refuse(event, reference, reason)
      {:retry, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp refuse(event, reference, reason) do
    Store.reject_source(reference, reason)

    Points.finish_event!(
      event,
      %{processing_status: :rejected, reason_code: "award_refused"},
      actor: Store.system()
    )

    %{id: event.id, status: :rejected}
  end

  defp award(event) do
    rule = event.rule_snapshot

    case Rules.base_micro(rule) do
      {:ok, requested} ->
        award_amount(event, rule, requested)

      {:error, reason} ->
        Points.finish_event!(
          event,
          %{processing_status: :rejected, reason_code: to_string(reason)},
          actor: Store.system()
        )

        %{id: event.id, status: :rejected}
    end
  end

  defp award_amount(event, rule, requested) do
    caps = caps(event, rule)

    case {rule, allowed(caps, requested, rule)} do
      # A one-time award already earned: the account's one entry for it stands.
      {%{"category" => "milestone"}, {0, reason}} ->
        Points.finish_event!(event, %{processing_status: :capped, reason_code: reason},
          actor: Store.system()
        )

        %{id: event.id, status: :capped}

      {_rule, {base, reason}} ->
        append(event, rule, requested, caps, base, reason)
    end
  end

  defp append(event, rule, requested, caps, base, reason) do
    if base > 0 do
      Enum.each(caps, fn {_kind, cap} ->
        Points.consume_cap!(cap, base, actor: Store.system())
      end)
    end

    entry =
      Points.append_entry!(
        %{
          program_id: event.program_id,
          event_id: event.id,
          award_key: event.award_key,
          account_id: event.account_id,
          rule_id: event.rule_id,
          rule_version: rule["version"],
          source_app: event.source_app,
          actor_kind: event.actor_kind,
          actor_id: event.actor_id,
          category: rule["category"],
          milestone_key: rule["milestone_key"],
          points_micro_delta: base,
          cap_reduction_micro: requested - base,
          earned_at: event.source_action_at,
          reason_code: reason
        },
        actor: Store.system()
      )

    Store.follow_period_bonus(entry)

    status = if base == 0, do: :capped, else: :confirmed

    Points.finish_event!(event, %{processing_status: status, reason_code: reason},
      actor: Store.system()
    )

    %{id: event.id, status: status}
  end

  defp caps(event, rule) do
    lifetime? = rule["period"] == "lifetime"
    program = if lifetime?, do: "lifetime", else: event.program_id
    scope = Rules.count_scope(rule)

    count =
      if rule["count"],
        do: [
          {:count,
           Store.cap(
             event.account_id,
             program,
             scope,
             Rules.window(rule["period"], event.source_action_at)
           )}
        ],
        else: []

    daily =
      case Rules.allowance_scope(rule) do
        nil ->
          []

        scope ->
          [
            {:daily,
             Store.cap(
               event.account_id,
               event.program_id,
               scope,
               Rules.window("day", event.source_action_at)
             )}
          ]
      end

    # Provider/registration proof cannot be handed to another account for a new
    # milestone. Account 0 is reserved for these restricted global proof claims.
    subject =
      if lifetime? and event.evidence["subject_key"] do
        scope = "subject:" <> Store.digest({scope, event.evidence["subject_key"]})

        [
          {:subject,
           Store.cap(0, "lifetime", scope, Rules.window("lifetime", event.source_action_at))}
        ]
      else
        []
      end

    count ++ daily ++ subject
  end

  defp allowed(caps, requested, rule) do
    exhausted =
      Enum.any?(caps, fn
        {:count, cap} -> cap.award_count >= rule["count"]
        {:subject, cap} -> cap.award_count >= 1
        _ -> false
      end)

    if exhausted do
      {0, "allowance_used"}
    else
      base =
        Enum.reduce(caps, requested, fn
          {:daily, cap}, base ->
            min(base, max(0, rule["daily_caps_micro"][cap.cap_scope] - cap.points_micro))

          _, base ->
            base
        end)

      {base, if(base < requested, do: "daily_cap", else: "qualified")}
    end
  end
end
