defmodule RegentsWeb.Techtree.PublicPagesController do
  @moduledoc """
  Security's sample report, a committed Markdown document, as a page in
  Techtree's frame. Its header shows the account the session pipeline found, as
  the live pages' does (`RegentsWeb.Live.Session`).
  """

  use RegentsWeb, :controller

  alias Regents.Account.AccessContext
  alias Regents.Account.Actors.Human
  alias Regents.Account.Formation
  alias RegentsWeb.Techtree.Layouts
  alias RegentsWeb.Techtree.PublicPagesHTML

  def show(conn, _params) do
    page = PublicPagesHTML.page(conn.request_path)

    render(conn, :show,
      page: page,
      page_title: page.title,
      page_description: Layouts.description(conn.request_path),
      current_path: conn.request_path,
      account_control: account_control(conn.assigns.current_human_account)
    )
  end

  defp account_control(nil), do: AccessContext.account_control(AccessContext.anonymous())

  defp account_control(account) do
    regent =
      case Formation.get_my_regent(actor: %Human{human_account_id: account.id}) do
        {:ok, regent} -> regent
        _no_regent -> nil
      end

    AccessContext.account_control(AccessContext.human(account), regent)
  end
end
