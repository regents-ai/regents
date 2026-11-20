defmodule RegentsWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.

  The page carries the site's bar signed out, as every page does. It reads no
  session and no account, so it still renders when the database or the session
  is what failed: the bar is drawn for an anonymous visitor, and the theme comes
  from its cookie alone. The page loads no script, so the bar's product menu
  opens (the browser's own popover) while Sign in and the theme switch only show.
  """
  use RegentsWeb, :html

  alias Regents.Account.AccessContext
  alias RegentsWeb.Components.Shell

  def render(template, assigns) do
    assigns = assigns |> Map.new() |> Map.put_new(:__changed__, nil)

    cookie_theme =
      case assigns[:conn] do
        %Plug.Conn{} = conn -> Plug.Conn.fetch_cookies(conn).req_cookies["regent_theme"]
        _ -> nil
      end

    theme = Enum.find([assigns[:theme], cookie_theme], &(&1 in ["light", "dark"]))

    assigns =
      assign(assigns,
        title: headline(template),
        theme: theme,
        account_control: AccessContext.account_control(AccessContext.anonymous())
      )

    ~H"""
    <!DOCTYPE html>
    <html
      lang="en"
      data-product="regents"
      data-brand={Regent.Site.brand("regents")}
      data-home={Application.fetch_env!(:regents, :home_colour)}
      data-theme={@theme}
    >
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title} · Regents Labs</title>
        <link rel="stylesheet" href="/assets/js/app.css" />
      </head>
      <body>
        <Shell.site_bar product="regents" account_control={@account_control} />
        <Regent.Structure.frame>
          <Regent.Structure.row rail={false}>
            <main class="rg-inset">
              <p>Regents Labs</p>
              <h1 class="rg-hero-title">{@title}</h1>
              <p><a class="rg-button rg-button--secondary" href="/">Go to the homepage</a></p>
              <nav aria-label="Recovery links">
                <ul>
                  <li :for={{label, path} <- RegentsWeb.PublicDocuments.recovery_links()}>
                    <a href={path}>{label}</a>
                  </li>
                </ul>
              </nav>
            </main>
          </Regent.Structure.row>
        </Regent.Structure.frame>
      </body>
    </html>
    """
  end

  defp headline("404" <> _format), do: "We can’t find that page"
  defp headline(_template), do: "Something went wrong"
end
