defmodule AshPlatformWeb.LegalController do
  @moduledoc "Serves the public Privacy Policy and Terms of Use."

  use AshPlatformWeb, :controller

  def privacy(conn, _params), do: show(conn, :privacy)
  def terms(conn, _params), do: show(conn, :terms)

  defp show(conn, id) do
    document = AshPlatform.Legal.document(id)
    render(conn, :show, page_title: document.title, document: document)
  end
end

defmodule AshPlatformWeb.LegalHTML do
  @moduledoc false

  use AshPlatformWeb, :html

  def show(assigns) do
    ~H"""
    <div class="rl-root legal-root rg-sheet rg-frame">
      <header class="legal-header">
        <a href={~p"/"} class="legal-home">Regents Labs</a>
        <nav class="legal-nav" aria-label="Legal">
          <a href={~p"/privacy"} aria-current={if(@document.id == :privacy, do: "page")}>
            Privacy
          </a>
          <a href={~p"/terms"} aria-current={if(@document.id == :terms, do: "page")}>Terms</a>
        </nav>
      </header>
      <main class="legal-page">
        {@document.html}
      </main>
    </div>
    """
  end
end
