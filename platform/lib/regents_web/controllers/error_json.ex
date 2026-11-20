defmodule RegentsWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  alias RegentAgentAccess.Recovery
  alias RegentsWeb.PublicDocuments

  # An address the site does not serve is `operation_unknown`, never the
  # `not_found` of a record that is missing.
  def render("404.json", %{reason: %Phoenix.Router.NoRouteError{}}),
    do: Recovery.json("Operation Unknown", hint())

  # By default, Phoenix returns the status message from
  # the template name. For example, "500.json" becomes
  # "Internal Server Error".
  def render(template, _assigns) do
    template
    |> Phoenix.Controller.status_message_from_template()
    |> Recovery.json(hint())
  end

  defp hint,
    do:
      "See #{PublicDocuments.url("/docs")} and #{PublicDocuments.url("/openapi.json")} for supported requests."
end
