defmodule Regents.Keyfleet.Usage do
  @moduledoc """
  What each fleet uses of the site, one calendar month (UTC) at a time
  (`Regents.Keyfleet.Usage.Month`), counted every hour from the records that hold it
  (`Regents.Keyfleet.Usage.Count`) and shown to anyone on the fleet's Treasury page.
  Its notebook hours are counted from the machines its hub lists, read every
  hour (`Regents.Keyfleet.Usage.ReadHub`, `Regents.Keyfleet.Usage.Machine`). It only
  measures: nothing here limits, warns or stops a fleet.
  """
  use Ash.Domain

  resources do
    resource Regents.Keyfleet.Usage.Month do
      define :count_month, action: :count, args: [:fleet_id, :month]
      define :count_notebooks, action: :count_notebooks
      define :month_usage, action: :read, get_by: [:fleet_id, :month], not_found_error?: false
    end

    resource Regents.Keyfleet.Usage.Machine do
      define :record_machines, action: :record
    end
  end

  @doc "The fleet's usage this month so far, as last counted, or nil before its first count."
  def this_month(fleet_id),
    do: month_usage!(fleet_id, Date.beginning_of_month(Date.utc_today()))
end
