defmodule Regents.Techtree.Factory do
  @moduledoc """
  Techtree Uplift Factory order intake, state machine, and `OrderBridge`
  operator domain (`techtree_app.job_orders`).

  All callers (controllers, LiveViews, MCP tools) interact exclusively through
  these Ash domain code interfaces rather than calling `Ash.*` or `Repo.*`
  directly.
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Techtree.Factory.Order do
      define :request_order, action: :request
      define :list_my_orders, action: :mine
      define :get_my_order, action: :own, get_by: [:id], not_found_error?: false
      define :cancel_order, action: :cancel

      define :list_bridge_orders, action: :bridge_list
      define :get_bridge_order, action: :bridge_get, get_by: [:id], not_found_error?: false

      define :get_bridge_materials,
        action: :bridge_materials,
        get_by: [:id],
        not_found_error?: false

      define :check_order, action: :check
      define :quote_order, action: :set_quote
      define :mark_order_paid, action: :mark_paid
      define :expire_order, action: :expire
      define :refuse_order, action: :refuse
      define :claim_order, action: :claim
      define :deliver_order, action: :deliver
      define :fail_order, action: :fail
    end
  end
end
