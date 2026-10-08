defmodule Regents.Credits.Credited do
  @moduledoc """
  When a Credits purchase is credited, asks Regent Points to consider it, inside
  the credit's transaction. Points decides whether the purchase earns; while its
  rule is off nothing is queued.
  """

  @behaviour RegentCredits.Credited

  alias Regents.Actors.System

  @impl true
  def credited(purchase) do
    reference = %{
      rule_id: "credits.purchase_settled",
      source_app: "regents",
      source_kind: "credits_purchase",
      source_event_key: purchase.id
    }

    {:ok, _} = RegentPoints.record_event(reference, actor: %System{})
    :ok
  end
end
