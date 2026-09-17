defmodule AshPlatformWeb.ErrorMD do
  @moduledoc "Public recovery instructions without private request or exception details."

  def render(template, _assigns) do
    title = Phoenix.Controller.status_message_from_template(template)

    "# #{title}\n\nThis request could not be completed. Use these public entry points to continue:\n\n" <>
      AshPlatformWeb.PublicDocuments.recovery_markdown() <> "\n"
  end
end
