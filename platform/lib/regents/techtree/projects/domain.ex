defmodule Regents.Techtree.Projects do
  @moduledoc """
  The projects Techtree delivered to customers (`Regents.Techtree.Projects.Project`):
  each one holds the verified package a piece of work produced (`uplift-package/1`
  or `uplift-package/2`), its structured receipt, and its Markdown report.

  Customers read their own projects signed in or through their paired agent.
  Autonomous delivery (`deliver_project/2`) is system-actor only and validates
  every archive byte against `manifest.json` before storing.
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Techtree.Projects.Project do
      define :list_my_projects, action: :mine
      define :get_my_project, action: :own, get_by: [:id], not_found_error?: false
      define :get_my_package, action: :own_package, get_by: [:id], not_found_error?: false

      define :get_project_for_system,
        action: :system_by_id,
        get_by: [:id],
        not_found_error?: false

      define :deliver_project, action: :deliver
    end
  end
end
