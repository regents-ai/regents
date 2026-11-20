defmodule RegentsWeb.Patchbay.BusyPage do
  @moduledoc """
  The answer to a Patchbay page the database was too busy to read
  (`Regents.Patchbay.DatabaseBusy`): 503, with Retry-After saying when to open
  it again, as a page inside Patchbay's frame or as Markdown. The log names
  the kind of busy.

  Its Try again link opens `:try_again`, by default the address that was
  opened. `:note` says anything that did happen before the page could not be
  read.
  """

  use RegentsWeb, :html

  import Phoenix.Controller, only: [current_path: 1, get_format: 1, put_view: 2, render: 3]

  import Plug.Conn,
    only: [
      merge_assigns: 2,
      put_resp_content_type: 2,
      put_resp_header: 3,
      put_status: 2,
      send_resp: 3
    ]

  require Logger

  alias Regents.Patchbay.DatabaseBusy
  alias RegentsWeb.Patchbay.Layouts
  alias RegentsWeb.Patchbay.PublicDocuments

  @spec respond(Plug.Conn.t(), :no_connection | :timeout, keyword()) :: Plug.Conn.t()
  def respond(conn, kind, options \\ []) do
    Logger.warning("Page unavailable: #{inspect(kind)}")
    note = Keyword.get(options, :note)

    conn =
      conn
      |> put_resp_header("retry-after", DatabaseBusy.retry_after())
      |> put_status(:service_unavailable)

    case get_format(conn) do
      "md" ->
        conn
        |> put_resp_content_type("text/markdown")
        |> send_resp(:service_unavailable, markdown(note))

      "html" ->
        conn
        |> merge_assigns(PublicDocuments.page(:busy) ++ Layouts.frame(conn, []))
        |> put_view(html: __MODULE__)
        |> render(:busy,
          try_again: Keyword.get_lazy(options, :try_again, fn -> current_path(conn) end),
          note: note
        )
    end
  end

  defp markdown(note) do
    """
    # Patchbay is too busy to open this page right now.

    #{if note, do: note <> "\n\n"}Wait a moment, then open it again. The answer says how many seconds in its Retry-After header.
    """
  end

  attr :try_again, :string, required: true
  attr :note, :string, default: nil

  @doc "The busy page: what happened, and the way back to the page or home."
  def busy(assigns) do
    ~H"""
    <main class="pb-error">
      <Regent.Structure.panel class="pb-error-inner">
        <h1>Busy</h1>
        <p :if={@note} class="pb-error-lede">{@note}</p>
        <p class="pb-error-lede">Wait a moment, then open it again.</p>
        <a class="pb-cta rg-button rg-button--primary" href={@try_again}>
          <span class="rg-button__label">Try again</span>
        </a>
        <a href={~p"/patchbay"}>Home</a>
      </Regent.Structure.panel>
    </main>
    """
  end
end
