defmodule RegentsWeb.ErrorMD do
  @moduledoc "Public recovery instructions without private request or exception details."

  alias RegentsWeb.PublicDocuments

  def render(template, _assigns) do
    links =
      for {label, path} <- PublicDocuments.recovery_links(),
          do: {label, PublicDocuments.url(path)}

    template
    |> Phoenix.Controller.status_message_from_template()
    |> RegentAgentAccess.Recovery.markdown(links)
  end
end
