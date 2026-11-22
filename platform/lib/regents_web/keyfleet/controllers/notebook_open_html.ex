defmodule RegentsWeb.Keyfleet.NotebookOpenHTML do
  @moduledoc """
  The page that sends a person's one-time notebook code to their fleet's
  notebook host (`RegentsWeb.Keyfleet.NotebookOpenController`), in Keyfleet's own look.
  Its one script sends the form as soon as the page loads; without scripts, the
  button does. Someone this site sent on moments ago and who is back already is
  asked to press the button instead, so a browser that won't keep the notebook
  sign-in is never sent round and round.
  """
  use RegentsWeb, :html

  def entry(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-brand="platform" data-theme={@theme}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Notebooks · {@fleet_name} · Keyfleet</title>
        <link rel="stylesheet" href={~p"/assets/js/app.css"} />
      </head>
      <body>
        <Regent.Utility.page
          title={if @by_itself?, do: "Opening notebooks", else: "Open notebooks"}
          id="notebook-entry-page"
        >
          <p :if={!@by_itself?}>
            If this page comes back after you press, your browser is blocking the notebooks’ sign-in.
          </p>
          <:actions>
            <form id="notebook-entry" method="post" action={@entry.action}>
              <input type="hidden" name="code" value={@entry.code} />
              <input type="hidden" name="to" value={@entry.to} />
              <button type="submit" class="rg-button rg-button--primary">Open notebooks</button>
            </form>
          </:actions>
          <:note>
            <a href={@workspace_path}>Back to the workspace</a>
          </:note>
        </Regent.Utility.page>
        <script :if={@by_itself?} nonce={@nonce}>
          document.getElementById("notebook-entry").submit()
        </script>
      </body>
    </html>
    """
  end
end
