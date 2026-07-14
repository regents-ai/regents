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
  attr :reactions_enabled, :boolean, default: false
  attr :reaction_summaries, :map, default: %{}

  def comment_ledger(assigns) do
    ~H"""
    <section id="comment-ledger" class="comment-ledger" aria-labelledby="comment-ledger-title">
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
        <label for="comment-body">Add a comment</label>
        <textarea
          id="comment-body"
          name="comment[body]"
          rows="4"
          required
          autocomplete="off"
        >{@draft}</textarea>
        <div class="comment-ledger__composer-actions">
          <p>Links, emphasis, code, and lists are supported.</p>
          <button type="submit">Post comment</button>
        </div>
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
            <div class="comment-ledger__body">{Markdown.to_safe_html(comment.body)}</div>
            <div
              :if={@reactions_enabled}
              class="comment-ledger__reactions"
              aria-label="Comment reactions"
            >
              <%= for {value, label} <- reaction_options() do %>
                <button
                  :if={@current_human_id}
                  type="button"
                  phx-click="react_comment"
                  phx-value-id={comment.id}
                  phx-value-reaction={value}
                  data-reaction-value={value}
                  aria-pressed={
                    to_string(reaction_summary(@reaction_summaries, comment.id).current == value)
                  }
                >
                  {label} {reaction_count(@reaction_summaries, comment.id, value)}
                </button>
                <span :if={is_nil(@current_human_id)} data-reaction-value={value}>
                  {label} {reaction_count(@reaction_summaries, comment.id, value)}
                </span>
              <% end %>
            </div>
            <button
              :if={@admin || comment.author_id == @current_human_id}
              type="button"
              phx-click="delete_comment"
              phx-value-id={comment.id}
              data-confirm="Delete this comment?"
            >
              Delete
            </button>
          </article>
        </li>
      </ol>
    </section>
    """
  end

  defp display_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %-d, %Y · %H:%M UTC")
  end

  defp reaction_options do
    [{:useful, "Useful"}, {:off_topic, "Off-topic"}, {:negative, "Negative"}]
  end

  defp reaction_count(summaries, comment_id, value) do
    summaries
    |> reaction_summary(comment_id)
    |> Map.fetch!(:counts)
    |> Map.fetch!(value)
  end

  defp reaction_summary(summaries, comment_id) do
    Map.get(summaries, comment_id, %{
      current: nil,
      counts: %{useful: 0, off_topic: 0, negative: 0}
    })
  end
end
