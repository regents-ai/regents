defmodule Regents.Techtree.Projects do
  @moduledoc """
  The projects Techtree's team delivered to customers, read only here: each one
  the package a piece of work produced, with its before and after, kept for the
  customer's account (`Regents.Techtree.Projects.Project`).

  The customer reads their own, signed in or through the agent they paired. This
  site reads the rows where they already are, in Techtree's own schema
  (`techtree_app`), with read actions only and no migration: finding a
  customer, delivering a project and withdrawing one stay on techtree.sh's team
  page, which writes these rows (`SOURCE.json` names what was not brought).
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Techtree.Projects.Project do
      define :list_my_projects, action: :mine
      define :get_my_project, action: :own, get_by: [:id], not_found_error?: false
      define :get_my_package, action: :own_package, get_by: [:id], not_found_error?: false
    end
  end
end
