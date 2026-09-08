defmodule AshPlatformWeb.Components.CommentLedger do
  @moduledoc false
  use Phoenix.Component

  alias AshPlatform.Discussions.Markdown
  alias AshPlatform.PublicIdentity

  attr :comments, :list, required: true
  attr :status, :atom, required: true
  attr :notice, :map, default: nil
  attr :current_human_id, :integer, default: nil
  attr :admin, :boolean, default: false
  attr :request_id, :string, required: true
  attr :draft, :string, default: ""

  def comment_ledger(assigns) do
    ~H"""
    <section
      id="comment-ledger"
      class="comment-ledger rg-panel rg-panel--surface rg-panel__body"
      aria-labelledby="comment-ledger-title"
    >
      <header class="comment-ledger__heading">
        <div>
          <p class="comment-ledger__kicker">Discussion</p>
          <h2 id="comment-ledger-title">Comments</h2>
        </div>
        <p>Newest first · 2,000 characters</p>
      </header>

      <div
        :if={@notice}
        id="comment-ledger-status"
        class={"comment-ledger__notice comment-ledger__notice--#{@notice.tone}"}
        role={if(@notice.tone == :error, do: "alert", else: "status")}
        aria-live="polite"
        aria-atomic="true"
      >
        {@notice.message}
      </div>

      <form :if={@current_human_id} id="comment-form" phx-submit="post_comment">
        <input type="hidden" name="comment[client_request_id]" value={@request_id} />
        <Regent.Primitives.field id="comment-body" label="Add a comment">
          <textarea
            id="comment-body"
            name="comment[body]"
            rows="4"
            required
            autocomplete="off"
            aria-describedby="comment-body-guidance"
          >{@draft}</textarea>
        </Regent.Primitives.field>
        <div class="comment-ledger__composer-actions">
          <p id="comment-body-guidance">
            Markdown and LaTeX · 2,000 characters.
          </p>
          <Regent.Primitives.button type="submit">Post comment</Regent.Primitives.button>
        </div>
        <Regent.Primitives.disclosure
          summary="Formatting"
          class="comment-ledger__format-help"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          id="comment-ledger-details-0"
        >
          <p>
            Use headings, **bold**, *italic*, ~~strikethrough~~, lists, quotes, links, tables and fenced code.
          </p>
          <p>
            Inline math: <code>$x^2$</code>. Display math: <code>{"$$\\frac{a}{b}$$"}</code>. Dollar signs inside code stay literal.
          </p>
        </Regent.Primitives.disclosure>
      </form>

      <p :if={is_nil(@current_human_id)} class="comment-ledger__signed-out">
        Sign in to add a comment.
      </p>

      <p :if={@status == :error} class="comment-ledger__empty" role="alert">
        Comments are unavailable right now.
      </p>

      <p :if={@status == :ready && @comments == []} class="comment-ledger__empty">
        No comments yet.
      </p>

      <ol :if={@comments != []} class="comment-ledger__list">
        <li :for={comment <- @comments}>
          <article id={"comment-#{comment.id}"}>
            <header>
              <strong>{PublicIdentity.label(comment.author)}</strong>
              <time datetime={DateTime.to_iso8601(comment.inserted_at)}>
                {display_time(comment.inserted_at)}
              </time>
            </header>
            <div
              id={"comment-body-#{comment.id}"}
              class="comment-ledger__body"
              phx-hook="CommentMarkdown"
            >
              {Markdown.to_safe_html(comment.body)}
            </div>
            <Regent.Primitives.button
              :if={@admin || comment.author_id == @current_human_id}
              variant="quiet"
              type="button"
              phx-click="delete_comment"
              phx-value-id={comment.id}
              data-confirm="Delete this comment?"
            >
              Delete
            </Regent.Primitives.button>
          </article>
        </li>
      </ol>
    </section>
    """
  end

  defp display_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %-d, %Y · %H:%M UTC")
  end
end
