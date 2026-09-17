defmodule AshPlatformWeb.PublicDocuments do
  @moduledoc "Public documents only; never projects a signed-in page or account."

  def url(path), do: AshPlatformWeb.Endpoint.url() <> path

  def document("/"),
    do: %{title: "Regents Labs", markdown: AshPlatformWeb.HomeLive.agent_markdown()}

  def document("/privacy"),
    do: %{title: "Privacy Policy", markdown: AshPlatform.Legal.markdown(:privacy)}

  def document("/terms"),
    do: %{title: "Terms of Use", markdown: AshPlatform.Legal.markdown(:terms)}

  def document(_path), do: nil

  def recovery_links do
    [
      {"Home", "/"},
      {"Developer documentation", "/docs"},
      {"Agent guide", "/llms.txt"},
      {"OpenAPI", "/openapi.json"},
      {"Sitemap", "/sitemap.xml"}
    ]
  end

  def recovery_markdown do
    Enum.map_join(recovery_links(), "\n", fn {label, path} ->
      "- [#{label}](#{url(path)})"
    end)
  end
end
