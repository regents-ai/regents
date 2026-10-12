defmodule RegentsWeb.ErrorsAdmin do
  @moduledoc """
  Keeps the saved errors at /admin/errors for Credits admins: a signed-in
  account the Credits `:admins` setting names (REGENT_CREDITS_ADMINS). Anyone
  else gets the site's ordinary not-found page, so the page's existence is not
  shown either.

  As a plug it checks the request and sends the page's own content security
  policy, with a nonce for the one style and one script element the error
  dashboard writes into its page. As an `on_mount` hook it checks the socket the
  page connects with, then re-reads the sign-in on every navigation and press,
  so a sign-in that ends or lapses cannot keep acting on the page.
  """

  @behaviour Plug

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, get_connect_info: 2, redirect: 2]
  import Plug.Conn

  alias Regents.Accounts.SessionAuthority
  alias RegentsWeb.ContentSecurityPolicy

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case conn |> get_session() |> admin() do
      nil ->
        raise Phoenix.Router.NoRouteError, conn: conn, router: RegentsWeb.Router

      _admin ->
        nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()

        conn
        |> assign(:csp_nonce, nonce)
        |> put_resp_header("content-security-policy", ContentSecurityPolicy.errors(nonce))
    end
  end

  def on_mount(:default, _params, session, socket) do
    session = if connected?(socket), do: get_connect_info(socket, :session), else: session

    case admin(session) do
      nil ->
        {:halt, redirect(socket, to: "/")}

      {lineage, account} ->
        recheck = fn socket -> recheck(socket, lineage, account.id) end

        {:cont,
         socket
         |> attach_hook(:errors_admin_params, :handle_params, fn _params, _uri, socket ->
           recheck.(socket)
         end)
         |> attach_hook(:errors_admin_event, :handle_event, fn _event, _params, socket ->
           recheck.(socket)
         end)}
    end
  end

  defp admin(session) do
    case session |> SessionAuthority.claim() |> SessionAuthority.resolve() do
      {lineage, account} when is_binary(lineage) ->
        if Regents.Credits.admin?(account), do: {lineage, account}

      _signed_out ->
        nil
    end
  end

  defp recheck(socket, lineage, account_id) do
    if lineage |> SessionAuthority.leased_account(account_id) |> Regents.Credits.admin?(),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: "/")}
  end
end
