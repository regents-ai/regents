defmodule AshPlatformWeb.AutolaunchLive do
  @moduledoc false
  use Phoenix.Component

  import AshPlatformWeb.Components.CommentLedger

  attr :route_spec, :map, required: true
  attr :params, :map, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :featured_auctions, :list, required: true
  attr :recent_auctions, :list, required: true
  attr :top_tokens, :list, required: true
  attr :graduated_tokens, :list, required: true
  attr :records, :list, required: true
  attr :record, :map, default: nil
  attr :launch_drafts, :list, required: true
  attr :draft_fields, :map, required: true
  attr :draft_notice, :map, default: nil
  attr :regent, :map, default: nil
  attr :status, :atom, required: true
  attr :comments, :list, required: true
  attr :comments_status, :atom, required: true
  attr :comment_notice, :map, default: nil
  attr :comment_request_id, :string, required: true
  attr :comment_draft, :string, required: true
  attr :current_human_id, :integer, default: nil
  attr :comment_admin, :boolean, required: true

  def page(assigns) do
    ~H"""
    <.overview
      :if={@route_spec.route_id == :autolaunch}
      featured_auctions={@featured_auctions}
      recent_auctions={@recent_auctions}
      top_tokens={@top_tokens}
      graduated_tokens={@graduated_tokens}
      status={@status}
    />
    <.collection
      :if={@route_spec.route_id in [:autolaunch_auctions, :autolaunch_tokens]}
      kind={if(@route_spec.route_id == :autolaunch_auctions, do: :auctions, else: :tokens)}
      records={@records}
      status={@status}
    />
    <.detail
      :if={@route_spec.route_id in [:autolaunch_auction, :autolaunch_token]}
      kind={if(@route_spec.route_id == :autolaunch_auction, do: :auction, else: :token)}
      record_id={
        @params[
          if(@route_spec.route_id == :autolaunch_auction,
            do: "auction_id",
            else: "token_id"
          )
        ]
      }
      record={@record}
      status={@status}
      comments={@comments}
      comments_status={@comments_status}
      comment_notice={@comment_notice}
      comment_request_id={@comment_request_id}
      comment_draft={@comment_draft}
      current_human_id={@current_human_id}
      comment_admin={@comment_admin}
    />
    <.create
      :if={@route_spec.route_id == :autolaunch_create}
      account_control={@account_control}
      launch_drafts={@launch_drafts}
      draft_fields={@draft_fields}
      draft_notice={@draft_notice}
      regent={@regent}
    />
    """
  end

  attr :featured_auctions, :list, required: true
  attr :recent_auctions, :list, required: true
  attr :top_tokens, :list, required: true
  attr :graduated_tokens, :list, required: true
  attr :status, :atom, required: true

  defp overview(assigns) do
    ~H"""
    <section id="autolaunch-overview" class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch</p>
        <h1>Launch with public proof</h1>
        <p>
          Discover auctions, follow graduated tokens, and create a launch whose money actions
          remain under wallet control.
        </p>
        <nav class="autolaunch-actions" aria-label="Autolaunch actions">
          <.link patch="/autolaunch/auctions">Browse auctions</.link>
          <.link patch="/autolaunch/tokens">Browse tokens</.link>
          <.link patch="/autolaunch/create">Create a launch</.link>
        </nav>
      </header>

      <div class="autolaunch-market-grid">
        <.market_section title="Featured auctions" kind={:auction} records={@featured_auctions} />
        <.market_section title="Recently created" kind={:auction} records={@recent_auctions} />
        <.market_section title="Top tokens" kind={:token} records={@top_tokens} />
        <.market_section title="Recently graduated" kind={:token} records={@graduated_tokens} />
      </div>
      <p :if={@status == :error} class="autolaunch-empty" role="alert">
        Public launch records are unavailable right now.
      </p>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :kind, :atom, required: true
  attr :records, :list, required: true

  defp market_section(assigns) do
    ~H"""
    <section class="autolaunch-market-section">
      <h2>{@title}</h2>
      <p :if={@records == []}>No public records yet.</p>
      <ol :if={@records != []} class="autolaunch-record-list">
        <li :for={record <- @records}>
          <.link patch={record_path(@kind, record.id)}>
            <strong>{record_label(@kind, record)}</strong>
            <span>{record.summary || record_fallback(@kind)}</span>
          </.link>
        </li>
      </ol>
    </section>
    """
  end

  attr :kind, :atom, required: true
  attr :records, :list, required: true
  attr :status, :atom, required: true

  defp collection(assigns) do
    assigns =
      assign(assigns,
        title: if(assigns.kind == :auctions, do: "Auctions", else: "Tokens"),
        copy:
          if(
            assigns.kind == :auctions,
            do: "Active and completed auctions will appear here.",
            else: "Graduated and actively traded tokens will appear here."
          )
      )

    ~H"""
    <section id={"autolaunch-#{@kind}"} class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch</p>
        <h1>{@title}</h1>
        <p>{@copy}</p>
      </header>
      <.empty_state :if={@status == :ready && @records == []} copy="No public records yet." />
      <.empty_state :if={@status == :error} copy="Public records are unavailable right now." />
      <ol :if={@status == :ready && @records != []} class="autolaunch-record-list">
        <li :for={record <- @records}>
          <.link patch={record_path(collection_record_kind(@kind), record.id)}>
            <strong>{record_label(collection_record_kind(@kind), record)}</strong>
            <span>{record.summary || record_fallback(collection_record_kind(@kind))}</span>
          </.link>
        </li>
      </ol>
    </section>
    """
  end

  attr :kind, :atom, required: true
  attr :record_id, :string, required: true
  attr :record, :map, default: nil
  attr :status, :atom, required: true
  attr :comments, :list, required: true
  attr :comments_status, :atom, required: true
  attr :comment_notice, :map, default: nil
  attr :comment_request_id, :string, required: true
  attr :comment_draft, :string, required: true
  attr :current_human_id, :integer, default: nil
  attr :comment_admin, :boolean, required: true

  defp detail(assigns) do
    assigns = assign(assigns, :title, if(assigns.kind == :auction, do: "Auction", else: "Token"))

    ~H"""
    <article
      :if={@status == :ready && @record}
      id={"autolaunch-#{@kind}-detail"}
      class="autolaunch-page"
    >
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch · {@title}</p>
        <h1>{record_label(@kind, @record)}</h1>
        <p>{@record.summary || record_fallback(@kind)}</p>
      </header>
      <.comment_ledger
        comments={@comments}
        status={@comments_status}
        notice={@comment_notice}
        request_id={@comment_request_id}
        draft={@comment_draft}
        current_human_id={@current_human_id}
        admin={@comment_admin}
      />
    </article>

    <section
      :if={@status in [:empty, :error]}
      id={"autolaunch-#{@kind}-detail"}
      class="autolaunch-page autolaunch-empty"
      role={if(@status == :error, do: "alert", else: nil)}
    >
      <h1>{@title} not found</h1>
      <p>No public {@kind} exists at {@record_id}.</p>
      <.link patch={if(@kind == :auction, do: "/autolaunch/auctions", else: "/autolaunch/tokens")}>
        Return to {@title}s
      </.link>
    </section>
    """
  end

  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :launch_drafts, :list, required: true
  attr :draft_fields, :map, required: true
  attr :draft_notice, :map, default: nil
  attr :regent, :map, default: nil

  defp create(assigns) do
    ~H"""
    <section id="autolaunch-create" class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch · Create</p>
        <h1>Create a launch</h1>
        <p>
          Prepare the launch on the web, then review every bid and money action in your wallet.
        </p>
      </header>

      <section class="autolaunch-reputation" aria-labelledby="autolaunch-reputation-title">
        <div>
          <p class="autolaunch-kicker">Optional reputation</p>
          <h2 id="autolaunch-reputation-title">Strengthen the public signal</h2>
          <p>Connect all four when available. None is required to sign in or create.</p>
        </div>
        <ul>
          <li :for={network <- ["X", "Farcaster", "ENS", "World"]}>
            <span aria-hidden="true">◇</span> Verified {network}
          </li>
        </ul>
      </section>

      <.empty_state
        :if={@account_control.kind == :sign_in}
        copy="Sign in to prepare your launch."
      />

      <div :if={@account_control.kind == :signed_in && is_nil(@regent)} class="autolaunch-empty">
        <p>Form your Regent before creating a launch draft.</p>
        <.link patch="/formation">Open Formation</.link>
      </div>

      <section
        :if={@account_control.kind == :signed_in && @regent}
        class="autolaunch-draft-workspace"
        aria-labelledby="launch-draft-title"
      >
        <div>
          <p class="autolaunch-kicker">Private preparation</p>
          <h2 id="launch-draft-title">Draft the public launch identity</h2>
          <p>
            This saves a private draft for {@regent.display_name}. It does not create an auction,
            publish a token, or request a wallet action.
          </p>
        </div>

        <form id="create-launch-draft" phx-submit="create_launch_draft" class="autolaunch-draft-form">
          <label>
            <span>Launch title</span>
            <input
              type="text"
              name="launch_draft[title]"
              value={@draft_fields["title"]}
              maxlength="160"
              required
            />
          </label>
          <label>
            <span>Token name</span>
            <input
              type="text"
              name="launch_draft[token_name]"
              value={@draft_fields["token_name"]}
              maxlength="100"
              required
            />
          </label>
          <label>
            <span>Token symbol</span>
            <input
              type="text"
              name="launch_draft[symbol]"
              value={@draft_fields["symbol"]}
              maxlength="16"
              pattern="[A-Z0-9]+"
              autocapitalize="characters"
              required
            />
          </label>
          <label>
            <span>Public summary</span>
            <textarea name="launch_draft[summary]" maxlength="2000">{@draft_fields["summary"]}</textarea>
          </label>
          <button type="submit">Save private draft</button>
        </form>

        <p
          :if={@draft_notice}
          class={"autolaunch-draft-notice autolaunch-draft-notice--#{@draft_notice.tone}"}
          role="status"
        >
          {@draft_notice.message}
        </p>

        <div id="launch-drafts" class="autolaunch-drafts">
          <h2>Private drafts</h2>
          <p :if={@launch_drafts == []}>No launch drafts yet.</p>
          <article :for={draft <- @launch_drafts} id={"launch-draft-#{draft.id}"}>
            <p class="autolaunch-kicker">Private draft · {draft.symbol}</p>
            <h3>{draft.title}</h3>
            <p>{draft.token_name}</p>
            <p :if={draft.summary}>{draft.summary}</p>
          </article>
        </div>
      </section>
    </section>
    """
  end

  attr :copy, :string, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="autolaunch-empty">
      <p>{@copy}</p>
    </div>
    """
  end

  defp record_path(:auction, id), do: "/autolaunch/auctions/#{id}"
  defp record_path(:token, id), do: "/autolaunch/tokens/#{id}"

  defp record_label(:auction, record), do: record.title
  defp record_label(:token, record), do: "#{record.name} · #{record.symbol}"

  defp record_fallback(:auction), do: "No public summary yet."
  defp record_fallback(:token), do: "No public token summary yet."

  defp collection_record_kind(:auctions), do: :auction
  defp collection_record_kind(:tokens), do: :token
end
