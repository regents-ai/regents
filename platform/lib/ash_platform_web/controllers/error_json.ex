defmodule AshPlatformWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  alias AshPlatformWeb.PublicDocuments

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    template
    |> Phoenix.Controller.status_message_from_template()
    |> RegentAgentAccess.Recovery.json(
      "See #{PublicDocuments.url("/docs")} and #{PublicDocuments.url("/openapi.json")} for supported requests."
    )
  end
end
