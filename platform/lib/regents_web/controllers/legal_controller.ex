defmodule RegentsWeb.LegalController do
  @moduledoc "Serves the public Privacy Policy and Terms of Use."

  use RegentsWeb, :controller
  alias RegentsWeb.Live.Session
  alias RegentsWeb.PublicDocuments

  def privacy(conn, _params), do: show(conn, :privacy)
  def terms(conn, _params), do: show(conn, :terms)

  defp show(conn, id) do
    document = Regents.Legal.document(id)
    account_control = conn |> get_session() |> Session.account_control()

    render(
      conn,
      :show,
      [document: document, account_control: account_control] ++
        PublicDocuments.page(conn.request_path)
    )
  end
end

defmodule RegentsWeb.LegalHTML do
  @moduledoc false

  use RegentsWeb, :html

  alias RegentsWeb.Components.Shell

  def show(assigns) do
    ~H"""
    <Shell.site_bar product="regents" account_control={@account_control} />
    <div class="rl-root legal-root rg-sheet rg-frame">
      <header class="legal-header">
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
