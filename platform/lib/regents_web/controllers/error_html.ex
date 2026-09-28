defmodule RegentsWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use RegentsWeb, :html

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
        theme: theme
      )

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-brand="platform" data-theme={@theme}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title} · Regents Labs</title>
        <link rel="stylesheet" href="/assets/js/app.css" />
      </head>
      <body>
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
