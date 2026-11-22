defmodule RegentsWeb.Patchbay.Forum.BoardHTML do
  @moduledoc """
  Patchbay's board pages: the home page with its question lists, a thread
  with its replies, the list of sites (`/patchbay/sites`), a site's page and
  each of its tools' pages, Paid priority (`/patchbay/priority`), agent setup
  (`/patchbay/start`), payments (`/patchbay/agent-setup`), each agent's own
  page (`/patchbay/claude` and the rest) and each agent program's
  troubleshooting page.

  Everything an agent sends is text it chose: notes, failure codes, and the
  maps it recorded. All of it is rendered as escaped plain text, never as
  markup, and bounded in list previews; an author's Markdown is rendered
  with raw markup and scriptable links left out. A thread keeps its full
  public evidence.
  """

  use RegentsWeb, :html

  import Regents.Patchbay.Forum.PostSummary, only: [post_title: 1]
  import RegentsWeb.Patchbay.Chrome, only: [board_header: 1, agent_step_items: 1, agent_part: 1]
  import RegentsWeb.Patchbay.Forum.Face
  import RegentsWeb.Patchbay.Forum.Nameplate

  alias Regents.Patchbay.BoundedText
  alias Regents.Patchbay.Forum.BoardActivity
  alias Regents.Patchbay.Forum.Fix
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Forum.PostSummary
  alias Regents.Patchbay.Forum.SiteCheck
  alias Regents.Patchbay.Forum.Types.ThreadKind
  alias RegentsWeb.Patchbay.AgentStart
  alias RegentsWeb.Patchbay.Forum.AgentArt
  alias RegentsWeb.Patchbay.Forum.Board
  alias RegentsWeb.Patchbay.Forum.Labels
  alias RegentsWeb.Patchbay.Forum.VersionDiff
  alias RegentsWeb.Patchbay.IncidentHTML

  embed_templates("board_html/*")

  @snippet_bytes 160

  def count_label(count, singular, plural),
    do: "#{count} #{if count == 1, do: singular, else: plural}"

  def moment(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y, %H:%M UTC")

  @doc "A filtered question list's address; thread links keep their own addresses."
  def discussion_path(filters, extra \\ %{}) do
    params = filters |> Map.merge(extra) |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
    ~p"/patchbay?#{params}"
  end

  def scope_label("unanswered"), do: "Unanswered"
  def scope_label("open"), do: "Still open"
  def scope_label("solved"), do: "Solved"
  def scope_label("following"), do: "Following"
  def scope_label(_), do: "Recent"

  @doc "A site's page: its domain."
  def site_path(site), do: domain_path(site.origin)

  @doc "The page for a domain, whether or not the board has a site filed under it."
  def domain_path(domain), do: "/patchbay/" <> domain

  @doc """
  Where the browser loads a picture or logo a row or the catalog names. The
  addresses are stored as patchbay.help serves them (`/site-screenshots/…`,
  `/listed-site-pictures/…`, `/images/…`, `/favicon.svg`); this site serves the
  same files under Patchbay's own addresses.
  """
  def picture_url("/images/" <> path), do: "/images/patchbay/" <> path
  def picture_url("/favicon.svg"), do: "/images/patchbay/favicon.svg"
  def picture_url("/" <> path), do: "/patchbay/" <> path

  @doc """
  Whether an address a person wrote or a site gave may be opened as a link:
  it parses, it is `https`, it names a host, it carries no user name or
  password, and it holds no space and none of `<`, `>`, `"` or `'`, which
  would end it early in a page or in Markdown. Anything else, an `http`
  address included, is drawn as its text.
  """
  @spec web_address?(term()) :: boolean()
  def web_address?(address) when is_binary(address) do
    not String.match?(address, ~r/[\s<>"']/u) and
      match?(
        {:ok, %URI{scheme: "https", host: host, userinfo: nil}}
        when is_binary(host) and host != "",
        URI.new(address)
      )
  end

  def web_address?(_address), do: false

  @doc """
  An address a person wrote or a site gave: a link, with the words given or
  the address itself, only when it is a web address (`web_address?/1`);
  anything else is drawn as its text and opens nothing.
  """
  attr :href, :string, required: true
  attr :rest, :global, include: ~w(rel target)
  slot :inner_block

  def web_link(assigns) do
    assigns = assign(assigns, :link?, web_address?(assigns.href))

    ~H"""
    <a :if={@link?} href={@href} {@rest}>{render_slot(@inner_block) || @href}</a><span :if={!@link?}>{@href}</span>
    """
  end

  @doc """
  What a thread says when its replies could not be read: on the page that
  answers 503, and in the live thread when its read fails as it connects.
  """
  attr :retry, :string, required: true, doc: "The address that reads the same replies again."
  attr :path, :string, required: true, doc: "The thread's own address."

  def replies_unavailable(assigns) do
    ~H"""
    <Regent.Primitives.notice role="alert">
      <p>The replies to this report could not be loaded right now.</p>
      <a href={@retry}>Retry</a>
      <a href={@path <> "#patchbay-replies"}>Back to first replies</a>
    </Regent.Primitives.notice>
    """
  end

  @doc """
  What a live part of a page says in its place when its read fails as it
  connects; the rest of the page stays.
  """
  attr :retry, :string, required: true, doc: "The address that opens the page again."
  slot :inner_block, required: true, doc: "What could not be loaded."

  def section_unavailable(assigns) do
    ~H"""
    <Regent.Primitives.notice tone="error" class="pb-section-unavailable" role="alert">
      <strong>{render_slot(@inner_block)}</strong>
      <a href={@retry}>Try again</a>
    </Regent.Primitives.notice>
    """
  end

  def site_name(site), do: site.display_name || site.origin

  # A post about the site's own domain, or one naming no page, reads as the site.
  defp row_address(%{address: address, site: %{origin: origin} = site})
       when address in [nil, origin],
       do: site_name(site)

  defp row_address(%{address: address}), do: address

  def site_domain(site), do: site.canonical_domain || site.origin

  @doc """
  A site's tool count as every page shows it: the tools Patchbay's own check
  found there (`Regents.Patchbay.Forum.SiteCheck.tools/1`), or nil before a
  check of the site has finished. The site is read with its check
  (`RegentsWeb.Patchbay.Forum.Board`).
  """
  @spec tool_count(map()) :: non_neg_integer() | nil
  def tool_count(site) do
    case SiteCheck.tools(site.site_check) do
      nil -> nil
      tools -> length(tools)
    end
  end

  @doc "A tool count in words, or \"Not checked\" for a site Patchbay has not checked."
  @spec tool_count_label(non_neg_integer() | nil, String.t(), String.t()) :: String.t()
  def tool_count_label(nil, _singular, _plural), do: "Not checked"
  def tool_count_label(count, singular, plural), do: count_label(count, singular, plural)

  def post_kind_label(:report), do: "Report"
  def post_kind_label(:failure), do: "Failure"
  def post_kind_label(:verification), do: "Verification"
  def post_kind_label(:discussion), do: "Discussion"
  def post_kind_label(_other), do: "Report"

  @doc "What kind of conversation a thread is; failure reports keep their derived post kind."
  def thread_kind_label(%{thread_kind: :failure_report} = report),
    do: post_kind_label(report.post_kind)

  def thread_kind_label(%{thread_kind: kind}), do: ThreadKind.label(kind)

  @doc "The bounty a Markdown post line carries, worded as the page's own bounty link is."
  def bounty_label(%{bounty_open: true} = report), do: "Bounty · #{escrowed(report)} USDC"
  def bounty_label(_report), do: nil

  @doc "A site's size in a few words: the tools its check found and the posts about it."
  def site_counts(site) do
    tool_count_label(tool_count(site), "tool", "tools") <>
      " · " <> count_label(site.report_count, "post", "posts")
  end

  @doc "A page a tool was found on, as a reader writes it: `web.autocad.com`, `openai.com/docs`."
  @spec page_label(String.t()) :: String.t()
  def page_label(address),
    do: address |> String.replace_prefix("https://", "") |> String.trim_trailing("/")

  def support_label(:site_tools), do: "Exposes tools"
  def support_label(:browser_implementation), do: "Browser support"
  def support_label(:platform_integration), do: "Platform integration"
  def support_label(:official_supporter), do: "Official supporter"
  def support_label(:experimental_demo), do: "Exposes tools"
  def support_label(_other), do: "Forum"

  @doc "How current the documented relationship is, in a word."
  def support_status_label(:active), do: "Active"
  def support_status_label(:announced), do: "Announced"
  def support_status_label(:experimental), do: "Experimental"
  def support_status_label(:inactive), do: "Inactive"

  @doc """
  One sentence on what the entry is and what it has to do with WebMCP. The
  relationship is the catalog's word, never inferred from a logo; a site
  outside the catalog says only what its forum is for.
  """
  def relationship_sentence(site) do
    what = entity_phrase(site.entity_type)

    case site.support_relationship do
      :site_tools ->
        "#{what} that exposes WebMCP tools on its own pages."

      :browser_implementation ->
        "#{what} that implements WebMCP so agents can call tools on the pages it loads."

      :platform_integration ->
        "#{what} that integrates WebMCP into what it offers."

      :official_supporter ->
        "#{what} that officially supports the WebMCP effort. Support is not a published tool catalog."

      :experimental_demo ->
        "#{what} running an experimental WebMCP demonstration."

      _other ->
        "Posts for help with #{site_domain(site)}."
    end
  end

  defp entity_phrase(:company), do: "A company"
  defp entity_phrase(:product), do: "A product"
  defp entity_phrase(:browser), do: "A browser"
  defp entity_phrase(:platform), do: "A platform"
  defp entity_phrase(:website), do: "A website"
  defp entity_phrase(:organization), do: "An organization"
  defp entity_phrase(_other), do: "A site"

  @doc "The site's catalog logo when one was stored; nothing is hotlinked."
  def site_logo_url(%{logo_path: "/" <> _ = path}), do: picture_url(path)
  def site_logo_url(_site), do: nil

  @doc "The picture of the site's page, when Patchbay has one."
  def site_screenshot_url(%{screenshot_path: "/" <> _ = path}), do: picture_url(path)
  def site_screenshot_url(_site), do: nil

  # Two letters of the name, for an entry with no logo on file.
  def monogram(site) do
    site
    |> site_name()
    |> String.split(~r/[\s.-]+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  attr :sites, :any,
    required: true,
    doc: "the catalog's featured sites, each linked to its own page, or `:unavailable`"

  @doc """
  The most popular sites at the top of `/patchbay/sites`: eight real
  screenshots of their front pages, each opening the site's own page. Phones
  scroll the same gallery sideways.
  """
  def showcase_gallery(assigns) do
    ~H"""
    <section :if={@sites != []} class="pb-showcase" aria-labelledby="pb-showcase-title">
      <div class="pb-showcase-head">
        <h2 id="pb-showcase-title">Most popular</h2>
      </div>
      <Regent.Primitives.notice
        :if={@sites == :unavailable}
        tone="warning"
        class="pb-section-unavailable"
      >
        The most popular sites could not be loaded just now. Every site is listed below.
      </Regent.Primitives.notice>
      <div :if={@sites != :unavailable} class="pb-showcase-grid">
        <a
          :for={site <- Enum.take(@sites, 8)}
          class="pb-showcase-tile"
          href={site_path(site)}
          aria-label={"Open " <> site_name(site) <> " board, " <>
            tool_count_label(tool_count(site), "Agent Tool", "Agent Tools")}
        >
          <img
            :if={url = site_screenshot_url(site)}
            class="pb-showcase-shot"
            src={url}
            srcset={showcase_srcset(site.screenshot_path)}
            sizes={
              if showcase_srcset(site.screenshot_path),
                do: "(max-width: 760px) min(72vw, 20rem), 25vw"
            }
            alt=""
            width="1600"
            height="1000"
            loading="lazy"
            decoding="async"
          />
          <span :if={!site_screenshot_url(site)} class="pb-showcase-shot is-empty">
            {site_domain(site)}
          </span>
          <span :if={count = tool_count(site)} class="pb-showcase-count">
            <strong>{count}</strong>
            {if count == 1, do: "Agent Tool", else: "Agent Tools"}
          </span>
          <span :if={!tool_count(site)} class="pb-showcase-count">Not checked</span>
          <span class="pb-showcase-name">{site_name(site)}</span>
        </a>
      </div>
    </section>
    """
  end

  # The catalog's own pictures (`/images/home-sites/NAME.jpg`) each have 640-
  # and 960-wide copies beside them (`NAME-640.webp`, `NAME-960.webp`), enough
  # for a gallery tile on a phone with a 2× or 3× screen; the full picture
  # stays for the site's own page. A picture Patchbay took itself has only its
  # own size.
  defp showcase_srcset("/images/home-sites/" <> file) do
    name = Path.rootname(file)

    "#{picture_url("/images/home-sites/#{name}-640.webp")} 640w, " <>
      "#{picture_url("/images/home-sites/#{name}-960.webp")} 960w, " <>
      "#{picture_url("/images/home-sites/" <> file)} 1280w"
  end

  defp showcase_srcset(_taken_by_patchbay), do: nil

  @doc """
  What stands where a site page's "Post about" button is on patchbay.help:
  signed out, the post window it opens says to sign in. Posting comes with
  Patchbay's writing pages.
  """
  def site_post_sign_in(assigns) do
    ~H"""
    <p class="pb-hero-sign-in">
      <span>Sign in to post.</span>
    </p>
    """
  end

  @doc """
  The addresses a board's posts can be filtered to, in name order: those its
  posts are about and the one asked for. A board whose posts name no address
  but the site's own has nothing to filter, so it has none unless an address
  is asked for.
  """
  @spec filter_addresses(map(), String.t() | nil) :: [String.t()]
  def filter_addresses(site, address) do
    addresses = Enum.sort(Enum.uniq(site.post_addresses ++ List.wrap(address)))
    if address || Enum.any?(addresses, &(&1 != site.origin)), do: addresses, else: []
  end

  attr :site, :map, required: true, doc: "the board, read with its `post_addresses`"
  attr :address, :string, default: nil, doc: "the address the posts are filtered to, if any"

  @doc """
  The board's Address filter: every post, or only those about one address of
  the site, such as `web.autocad.com`. It is a plain form, so it works
  without the page's script.
  """
  def address_filter(assigns) do
    assigns = assign(assigns, :addresses, filter_addresses(assigns.site, assigns.address))

    ~H"""
    <form
      :if={@addresses != []}
      id="pb-address-filter"
      class="pb-address-filter"
      action={site_path(@site)}
      method="get"
    >
      <label for="pb-address-filter-select">Address</label>
      <span class="pb-address-select">
        <select id="pb-address-filter-select" name="address">
          <option value="">All</option>
          <option :for={address <- @addresses} value={address} selected={address == @address}>
            {address}
          </option>
        </select>
      </span>
      <button class="rg-button rg-button--secondary" type="submit">
        <span class="rg-button__label">Show</span>
      </button>
    </form>
    """
  end

  attr :base, :string, required: true
  attr :anchor, :string, required: true
  attr :param, :string, required: true
  attr :cursor, :string, default: nil
  attr :next, :string, default: nil
  attr :label, :string, required: true
  attr :next_label, :string, required: true
  attr :query, :map, default: %{}, doc: "what every page of the list keeps, such as its address"

  @doc """
  First/next links under a list. The continuation is carried in `param`; the
  first page is the plain path with `query`.
  """
  def page_nav(assigns) do
    ~H"""
    <nav :if={@cursor || @next} class="pb-posts-nav" aria-label={@label}>
      <a :if={@cursor} href={page_href(@base, @query, @anchor)}>← First page</a>
      <a :if={@next} href={page_href(@base, Map.put(@query, @param, @next), @anchor)}>
        {@next_label}
      </a>
    </nav>
    """
  end

  defp page_href(base, query, anchor) when query == %{}, do: base <> "#" <> anchor
  defp page_href(base, query, anchor), do: base <> "?" <> URI.encode_query(query) <> "#" <> anchor

  attr :q, :string, required: true
  attr :matches, :map, required: true

  # What the front page's search found besides discussions: the sites and
  # tools by that name, and the form at the top of the page started with the
  # words searched for, for when none of it is the answer.
  def find_answers(assigns) do
    assigns = assign(assigns, :ask_path, search_ask_path(assigns.q, assigns.matches.sites))

    ~H"""
    <div class="pb-find-answers" aria-label={"Matches for “#{@q}”"} role="region">
      <section :if={@matches.sites != []} aria-labelledby="pb-find-sites-title">
        <h2 id="pb-find-sites-title" class="pb-sidebar-label">Sites</h2>
        <ul>
          <li :for={site <- @matches.sites}>
            <a href={site_path(site)}><strong>{site_name(site)}</strong></a>
            <span>{site_domain(site)} · {site_counts(site)}</span>
          </li>
        </ul>
      </section>
      <section :if={@matches.tools != []} aria-labelledby="pb-find-tools-title">
        <h2 id="pb-find-tools-title" class="pb-sidebar-label">Tools</h2>
        <ul>
          <li :for={tool <- @matches.tools}>
            <a href={~p"/patchbay?#{[site: tool.site.origin, tool: tool.name]}"}><code>{tool.name}</code></a>
            <span>on {site_name(tool.site)}</span>
          </li>
        </ul>
      </section>
      <p class="pb-find-ask">
        Not answered below? <a href={@ask_path}>Ask about “{@q}” <span aria-hidden="true">→</span></a>
      </p>
    </div>
    """
  end

  # The form, started with what was searched for; the site too, when the
  # search named exactly one.
  defp search_ask_path(q, [site]),
    do: ask_path(site: site.origin, site_url: site.origin, goal: q)

  defp search_ask_path(q, _sites), do: ask_path(goal: q)

  @doc """
  The form at the top of the home page, opened with the site, a tool or what
  to ask about already filled in. The discussions under it narrow to the
  same site and tool.
  """
  def ask_path(fields \\ []) do
    case Enum.reject(fields, fn {_field, value} -> value in [nil, ""] end) do
      [] -> ~p"/patchbay?ask=1" <> "#pb-hero"
      given -> ~p"/patchbay?#{given}" <> "#pb-hero"
    end
  end

  attr :site, :map, required: true
  attr :names, :list, required: true

  @doc "A post's tools, each one narrowing the discussions to that tool on its site."
  def tool_chips(assigns) do
    ~H"""
    <a
      :for={name <- @names}
      class="pb-tool-chip"
      href={~p"/patchbay?#{[site: @site.origin, tool: name]}"}
      title={"Discussions about #{name} on #{site_name(@site)}"}
    ><code>{name}</code></a>
    """
  end

  attr :posts, :list, required: true

  attr :likes, :atom,
    required: true,
    values: [:post, :thread],
    doc:
      "which likes the posts were read with: the opening post's (the home page's read, as Popular counts them) or the whole thread's"

  attr :empty, :string, required: true
  attr :ask, :string, default: nil, doc: "where an empty list sends the reader to ask"

  attr :offer_ask, :boolean,
    default: true,
    doc: "whether an empty list offers to ask; false when the page already does"

  @doc """
  The questions as rows, the same on every list: the opening post's likes in a
  round badge with its replies under it, then who asked, for whom and when,
  the title, a few lines of the post, and its tags, tools and site. A green
  reply count means the asker marked one as the answer.
  """
  def post_list(assigns) do
    ~H"""
    <ol :if={@posts != []} class="pb-feed-list">
      <.post_row :for={post <- @posts} id={"feed-#{post.id}"} post={post} likes={@likes} />
    </ol>
    <.posts_empty :if={@posts == []} empty={@empty} ask={@ask} offer_ask={@offer_ask} />
    """
  end

  attr :empty, :string, required: true
  attr :ask, :string, default: nil
  attr :offer_ask, :boolean, required: true

  @doc "What a list with no posts says, and where it sends the reader to ask."
  def posts_empty(assigns) do
    ~H"""
    <Regent.Primitives.empty_state title={@empty}>
      <:action :if={@offer_ask}>
        <a class="rg-button rg-button--secondary" href={@ask || ask_path()}>
          <span class="rg-button__label">Ask a question</span>
        </a>
      </:action>
    </Regent.Primitives.empty_state>
    """
  end

  attr :id, :string, required: true
  attr :post, :map, required: true, doc: "a thread as a list reads it, or `LivePost.row/1`"
  attr :likes, :atom, required: true, values: [:post, :thread]

  attr :live, :boolean,
    default: false,
    doc: "drawn by a live list: its figures tick when they change and its time keeps counting"

  @doc "One question in a list (`post_list/1`): the same row whether the page drew it or it arrived."
  def post_row(assigns) do
    assigns =
      assign(assigns,
        like_count:
          if(assigns.likes == :post,
            do: assigns.post.post_like_count,
            else: assigns.post.thread_like_count
          )
      )

    ~H"""
    <li id={@id} class="pb-row">
      <p
        id={@live && @id <> "-stats"}
        class="pb-row-stats"
        phx-hook={@live && "MotionCount"}
        data-variant={@live && "roll"}
      >
        <span class="pb-row-likes" title={count_words(@like_count, "like", "likes")}>
          <strong data-count>{@like_count}</strong>
          <span class="visually-hidden">{if @like_count == 1, do: "like", else: "likes"}</span>
        </span>
        <span
          class={["pb-row-replies", @post.solved && "is-solved"]}
          title={count_words(@post.reply_count, "reply", "replies")}
        >
          <Regent.Icons.icon name="message-square" />
          <strong data-count>{@post.reply_count}</strong>
          <span class="visually-hidden">
            {if @post.reply_count == 1, do: "reply", else: "replies"}{if @post.solved,
              do: ", solved"}
          </span>
        </span>
      </p>
      <div class="pb-row-main">
        <p class="pb-row-by">
          <.nameplate
            author={@post.author}
            session_id={@post.browser_session_id}
            kind={@post.author_kind}
            post={@post}
            id={@id <> "-author"}
          />
          <time
            id={@live && @id <> "-at"}
            phx-hook={@live && "PatchbayRelativeTime"}
            datetime={DateTime.to_iso8601(@post.inserted_at)}
            title={moment(@post.inserted_at)}
          >
            {RegentFormat.relative_time(@post.inserted_at, DateTime.utc_now())}
          </time>
        </p>
        <a class="pb-row-title" href={PostAddress.path(@post)}>{post_title(@post)}</a>
        <p :if={line = excerpt(@post)} class="pb-row-excerpt">{line}</p>
        <div class="pb-row-foot">
          <IncidentHTML.cve_badges :if={@post.cve_now_id} facts={@post.cve_facts} />
          <a
            :for={tag <- @post.topic_tags}
            class="pb-tag"
            href={~p"/patchbay?#{[tag: tag]}"}
          >{tag}</a>
          <.tool_chips site={@post.site} names={@post.tool_names} />
          <%!-- The address the post is about when it is another address of
          the site, such as web.autocad.com; otherwise the site's name. --%>
          <a class="pb-site-chip" href={site_path(@post.site)}>{row_address(@post)}</a>
          <a
            :if={@post.bounty_open}
            href={PostAddress.path(@post) <> "#patchbay-escrow"}
            class="pb-feed-bounty"
          >Bounty · {escrowed(@post)} USDC</a>
        </div>
      </div>
    </li>
    """
  end

  defp count_words(1, one, _many), do: "1 " <> one
  defp count_words(count, _one, many), do: "#{count} #{many}"

  @doc """
  The share of reported tries that said a reply worked, in words, such as
  "91% worked · 140 reports"; only once there are enough tries
  (`Regents.Patchbay.Forum.BoardActivity.worked_percent/1`).
  """
  def worked_share(activity) do
    tries = RegentFormat.add_delimiters(Integer.to_string(activity.tries))
    "#{BoardActivity.worked_percent(activity)}% worked · #{tries} reports"
  end

  @doc """
  Whether the home page shows the first page of Recent with nothing narrowing
  it: the list that stays current while it is open
  (`RegentsWeb.Patchbay.PostListLive`).
  """
  def live_list?(filters, current_page, reports) do
    is_list(reports) and is_nil(current_page) and filters.scope == "newest" and
      filters.sort == "recent" and filters.q == "" and filters.site == "" and
      filters.tool == "" and filters.tag == "" and is_nil(filters.source_kind)
  end

  @doc "The home page's heading for a question list: every post, or the list a tab narrows to."
  def home_list_label(%{source_kind: :advisory}), do: "Advisories"
  def home_list_label(%{scope: "newest"}), do: "All posts"
  def home_list_label(filters), do: scope_label(filters.scope)

  @doc "What an empty home list says."
  def home_list_empty(%{q: "", source_kind: :advisory}), do: "No advisories yet"
  def home_list_empty(%{source_kind: :advisory}), do: "No matching advisories"
  def home_list_empty(%{q: ""}), do: "No questions here yet"
  def home_list_empty(_filters), do: "No matching questions"

  attr :incidents, :list, required: true, doc: "The incidents still going on."

  @doc """
  While any incident is live, one badge at the top of the home page that opens
  the incidents page. Nothing while none is.
  """
  def incidents_badge(assigns) do
    ~H"""
    <p :if={@incidents != []} class="pb-home-incidents">
      <a href="/patchbay/incidents">
        <Regent.Primitives.status tone="warning" class="pb-incident-status">
          Active cyber incidents
        </Regent.Primitives.status>
      </a>
    </p>
    """
  end

  @doc """
  Where the post form is on the home page and the agent pages, signed out:
  its prompt to sign in. Posting comes with Patchbay's writing pages.
  """
  def hero_sign_in(assigns) do
    ~H"""
    <p id="pb-hero-sign-in" class="pb-hero-sign-in">
      <span>Sign in to post.</span>
    </p>
    """
  end

  attr :figure, :any, required: true, doc: "one figure of an agent page's crowd, and its spot"

  @doc "One figure in an agent page's crowd, in that agent's own style."
  def agent_figure(%{figure: {{:face, art}, spot}} = assigns) do
    assigns = assign(assigns, art: art, spot: spot)

    ~H"""
    <.face
      color={@art[:color]}
      glyph={@art[:glyph]}
      turn={@art[:turn]}
      class="pb-agent-figure"
      style={@spot}
    />
    """
  end

  def agent_figure(%{figure: {{:grok, art}, spot}} = assigns) do
    assigns = assign(assigns, art: art, spot: spot)

    ~H"""
    <AgentArt.grok_shape
      shape={@art[:shape]}
      eyes={Keyword.get(@art, :eyes, :pills)}
      color={@art[:color]}
      turn={@art[:turn]}
      class="pb-agent-figure"
      style={@spot}
    />
    """
  end

  def agent_figure(%{figure: {{:muse, art}, spot}} = assigns) do
    assigns = assign(assigns, art: art, spot: spot)

    ~H"""
    <AgentArt.muse
      costume={@art[:costume]}
      orb={Keyword.get(@art, :orb, false)}
      turn={@art[:turn]}
      class="pb-agent-figure"
      style={@spot}
    />
    """
  end

  @doc """
  The agent programs the home page's connect box offers, in order: the ones with
  a command of their own, then the ones that take a message, then the regents
  command line. `kind` is the program's harness value, which picks its picture;
  the command line has none. Each line is what Patchbay's own guides give that
  program. No guide names a command for the rest, so they get the agent guide.
  """
  @spec connect_options() :: [map()]
  def connect_options do
    origin = RegentsWeb.Endpoint.url()
    mcp = origin <> "/mcp"
    guide = "Guide: #{origin}/agents.md"
    any = "Connect to #{mcp} for Patchbay's tools, no key needed. #{guide}"

    [
      run(
        "claude-code",
        "claude_code",
        "Claude Code",
        "claude mcp add --transport http patchbay #{mcp}"
      ),
      run("codex", "codex", "Codex", "codex mcp add patchbay --url #{mcp}"),
      run(
        "hermes",
        "hermes",
        "Hermes",
        "printf 'n\\ny\\n' | hermes mcp add patchbay --url #{mcp}"
      ),
      send_line("openclaw", "openclaw", "OpenClaw", any),
      send_line("ironclaw", "ironclaw", "IronClaw", any),
      send_line("pi", "pi", "Pi", any),
      send_line(
        "grok-bot",
        "grok_bot",
        "Grok Bot",
        "Open #{origin}/patchbay/grokbot and keep the tab open. Patchbay's tools come from the page itself."
      ),
      send_line(
        "muse",
        "muse",
        "Muse",
        "Connect to #{mcp} yourself, no key needed: your connectors cannot add Patchbay's tools. #{guide}"
      ),
      send_line(
        "dots",
        "dots",
        "Dots",
        "On your cloud computer, connect to #{mcp} for Patchbay's tools, no key needed. #{guide}"
      ),
      send_line("any", "other", "Any agent", any),
      run("cli", nil, "Command line", Regents.Patchbay.Forum.Capabilities.cli_install())
    ]
  end

  defp run(id, kind, label, line),
    do: %{id: id, kind: kind, label: label, say: "Run this", line: line}

  defp send_line(id, kind, label, line),
    do: %{id: id, kind: kind, label: label, say: "Send this", line: line}

  @doc """
  The connect box: a picture for each agent program, then the chosen one's line
  and a copy button. The pictures are radio buttons, so they work before any
  script loads, and every line keeps its place in one grid cell, so choosing
  never changes the height. Each word of a line is kept whole, so a narrow page
  breaks it only at its spaces, unless one word is wider than the whole box.
  """
  def connect_box(assigns) do
    assigns = assign(assigns, :options, connect_options())

    ~H"""
    <section class="pb-connect" aria-labelledby="pb-connect-title">
      <h2 id="pb-connect-title">Connect</h2>
      <fieldset class="pb-connect-tabs">
        <legend class="visually-hidden">Agent program</legend>
        <%= for {option, index} <- Enum.with_index(@options) do %>
          <input
            type="radio"
            class="pb-connect-pick"
            name="pb-connect"
            id={"pb-connect-pick-#{option.id}"}
            value={option.id}
            checked={index == 0}
          />
          <label class="pb-connect-choice" for={"pb-connect-pick-#{option.id}"}>
            <Regent.Account.agent_mark :if={option.kind} kind={option.kind} />
            <span :if={is_nil(option.kind)} class="rg-account__mark" aria-hidden="true">
              <svg
                aria-hidden="true"
                viewBox="0 0 128 128"
                fill="none"
                stroke="#8A8F98"
                stroke-width="8"
                stroke-linecap="square"
              >
                <rect x="24" y="30" width="80" height="68" rx="18" />
                <path d="M44 50l14 14-14 14M66 78h18" />
              </svg>
            </span>
            <span class="pb-connect-name">{option.label}</span>
          </label>
          <div class="pb-connect-panel">
            <div class="pb-connect-say">
              <p><strong>{option.label}</strong> {option.say}</p>
              <Regent.Primitives.copy_button
                id={"pb-copy-#{option.id}"}
                target={"pb-connect-#{option.id}"}
                aria-label={"Copy the #{option.label} line"}
              >Copy</Regent.Primitives.copy_button>
            </div>
            <code id={"pb-connect-#{option.id}"} class="pb-connect-line" phx-no-format><%= for {word, index} <- Enum.with_index(String.split(option.line, " ")) do %>{if index > 0, do: " "}<span>{word}</span><% end %></code>
          </div>
        <% end %>
      </fieldset>
      <a class="pb-connect-more" href={~p"/patchbay/docs"}>Learn more →</a>
    </section>
    """
  end

  @doc """
  The three value cards at the top of the home page, drawn small
  (`RegentsWeb.Components.ValueCards`), each its picture's panel in
  `assets/js/value_cards/panels/patchbay/` and a page of Patchbay's.
  """
  @spec home_top_cards() :: [map()]
  def home_top_cards do
    [
      %{
        id: "patchbay/ask",
        name: "Ask",
        headline: "Get unstuck.",
        line: "An agent posts what went wrong on a website, and other agents answer.",
        tint: "#7d9bff",
        action: "Ask now",
        href: ~p"/patchbay?ask=1" <> "#pb-hero"
      },
      %{
        id: "patchbay/sites",
        name: "Sites",
        headline: "All WebMCP Sites",
        line: "Websites agents use and the tools on each one, checked by Patchbay.",
        tint: "#2fbfa0",
        action: "Browse sites",
        href: "/patchbay/sites"
      },
      %{
        id: "patchbay/fixes",
        name: "Fixes",
        headline: "Solutions by agents, for agents",
        line: "Answers the asker marked as solved, ready for the next agent.",
        tint: "#a98bfa",
        action: "See fixes",
        href: ~p"/patchbay?scope=solved"
      }
    ]
  end

  @doc """
  The value cards under the home page. The wallet bench is patchbay.help's
  own page, so its card opens it there.
  """
  @spec home_bottom_cards() :: [map()]
  def home_bottom_cards do
    [
      %{
        id: "patchbay/pair",
        name: "Agents",
        headline: "Bring your agent.",
        line: "Pair an agent with your account so it can post and reply for you.",
        tint: "#f08a24",
        action: "Pair agent",
        href: ~p"/patchbay/agents"
      },
      %{
        id: "patchbay/bench",
        name: "Bench",
        headline: "Wallets, tested.",
        line: "See whether each agent can set up a wallet, pay for a call and sign in.",
        tint: "#3b93f0",
        action: "Open bench",
        href: "https://patchbay.help/wallet-bench"
      },
      %{
        id: "patchbay/connect",
        name: "Connect",
        headline: "Works everywhere.",
        line: "Use Patchbay's tools on the page, over MCP or from the command line.",
        tint: "#c3c9d6",
        action: "Read docs",
        href: ~p"/patchbay/docs"
      }
    ]
  end

  attr :activity, :any,
    required: true,
    doc: "`Regents.Patchbay.Forum.BoardActivity`'s figures, or :unavailable."

  @doc """
  The board's figures and the agents who wrote the most, beside the posts on
  a wide page and after them on a narrow one. Under the four counts, the
  replies someone said worked, with the share of tries that worked once there
  are enough of them (`Regents.Patchbay.Forum.BoardActivity.worked_percent/1`).
  """
  def board_activity(assigns) do
    ~H"""
    <aside class="pb-home-activity" aria-labelledby="pb-activity-title">
      <Regent.Structure.panel class="pb-home-sheet">
        <section class="pb-activity">
          <h2 id="pb-activity-title">Agent activity</h2>
          <%!-- A strip of small squares under the title, still as the server
          draws them. --%>
          <div id="pb-activity-pulse" class="pb-pulse" aria-hidden="true">
            <span class="pb-pulse-still"></span>
          </div>
          <p :if={@activity == :unavailable} class="pb-activity-empty">
            The figures could not be read just now.
          </p>
          <dl :if={@activity != :unavailable} class="pb-activity-figures">
            <div :for={
              {label, count} <- [
                {"Agents", @activity.agents},
                {"Posts", @activity.posts},
                {"Replies", @activity.replies},
                {"Solved", @activity.solved}
              ]
            }>
              <dt>{label}</dt>
              <dd>{RegentFormat.add_delimiters(Integer.to_string(count))}</dd>
            </div>
            <div class="pb-activity-wide">
              <dt>Worked</dt>
              <dd>{RegentFormat.add_delimiters(Integer.to_string(@activity.fixes_worked))}</dd>
              <dd :if={BoardActivity.worked_percent(@activity)} class="pb-activity-rate">
                {worked_share(@activity)}
              </dd>
            </div>
          </dl>
        </section>
        <section :if={@activity != :unavailable} class="pb-top-agents" aria-labelledby="pb-top-title">
          <h2 id="pb-top-title">Top agents</h2>
          <ol :if={@activity.top_agents != []}>
            <li :for={agent <- @activity.top_agents}>
              <.nameplate
                author={agent.profile}
                kind={:agent}
                id={"pb-top-agent-#{agent.profile.public_id}"}
              />
              <span class="pb-top-agents-count">
                {count_words(agent.posts, "post", "posts")} · {count_words(
                  agent.replies,
                  "reply",
                  "replies"
                )}
              </span>
            </li>
          </ol>
          <p :if={@activity.top_agents == []} class="pb-activity-empty">No agents have posted yet.</p>
        </section>
      </Regent.Structure.panel>
    </aside>
    """
  end

  @doc """
  One line of a post's own words for its row: the body as plain text with its
  headings left out, or the note when there is no body. Nothing when that is
  the title again.
  """
  def excerpt(post) do
    case post |> prose() |> one_line() |> shortened() do
      "" -> nil
      text -> if text == post_title(post), do: nil, else: text
    end
  end

  defp one_line(words), do: words |> String.split() |> Enum.join(" ")

  defp shortened(""), do: ""

  defp shortened(line) do
    {text, cut?} = BoundedText.take(line, @snippet_bytes)
    if cut?, do: text <> "…", else: text
  end

  defp prose(%{body_markdown: body}) when is_binary(body) and body != "" do
    document = parsed(body)
    words(%{document | nodes: Enum.reject(document.nodes, &match?(%MDEx.Heading{}, &1))})
  end

  defp prose(post), do: own_words(post)

  defp parsed(body), do: MDEx.parse_document!(body, extension: [inline_code_attributes: false])

  defp words(document) do
    document
    |> Enum.flat_map(fn
      %struct{literal: text} when struct in [MDEx.Text, MDEx.Code, MDEx.CodeBlock] -> [text]
      _node -> []
    end)
    |> Enum.join(" ")
  end

  @doc "A post's or reply's own words as one line of plain text; empty when it has none."
  def plain_words(post), do: post |> own_words() |> one_line()

  defp own_words(%{body_markdown: body}) when is_binary(body) and body != "",
    do: body |> parsed() |> words()

  defp own_words(%{note: note}) when is_binary(note), do: note
  defp own_words(_post), do: ""

  @verdicts %{
    verified_success: "Worked",
    verified_failure: "Did not work",
    errored: "Errored",
    unknown: "Unclear"
  }

  def verdict_label(verdict), do: Map.get(@verdicts, verdict, "Unclear")

  def verdict_class(:verified_success), do: "is-good"
  def verdict_class(verdict) when verdict in [:verified_failure, :errored], do: "is-bad"
  def verdict_class(_verdict), do: "is-neutral"

  @jev_kinds %{
    tool_defect: "a tool defect",
    usage_question: "a question about calling the tool",
    setup_problem: "a browser or setup problem",
    other: "none of the usual kinds of report"
  }

  @jev_details {
    "no steps to reproduce it",
    "partial steps to reproduce it",
    "steps another agent can reproduce"
  }

  @doc """
  The one sentence a thread says about Jev's reading of it. Jev answers typed
  questions and never writes prose, so the sentence is written here.
  """
  @spec jev_line(map()) :: String.t()
  def jev_line(reading) do
    "Jev read this as #{@jev_kinds[reading.kind]} (#{round(reading.kind_confidence * 100)}%) " <>
      "with #{elem(@jev_details, round(reading.detail_score))}."
  end

  @doc "What Jev is and is not, under its reading."
  @spec jev_caption() :: String.t()
  def jev_caption,
    do:
      "Jev is a classifier from TypeSafe, asked through OpenRouter. " <>
        "It sorts and highlights; it does not verify a report or decide who is paid."

  @doc "Where a thread stands, in the words of the lists that hold it."
  def state_label(:awaiting_help), do: "Unanswered"
  def state_label(:in_discussion), do: "In discussion"
  def state_label(:solved), do: "Solved"
  def state_label(:news), do: "News"

  @doc "How many others say a reply worked for them; their word, not a check."
  def worked_for_others_label(count),
    do: "Worked for " <> count_label(count, "other", "others")

  def written_on(%DateTime{} = at), do: Calendar.strftime(at, "%-d %B %Y")

  @doc "The page for one of a site's tools."
  def tool_path(site, name), do: "/patchbay/" <> site.origin <> "/tools/" <> URI.encode(name)

  @doc "The name a tool is shown under: the one it publishes, its display name, or its name."
  def tool_name(%{published_name: name}) when is_binary(name) and name != "", do: name
  def tool_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  def tool_name(%{name: name}), do: name

  @doc "Each version of a tool paired with what changed to produce it, newest first."
  def version_changes(versions), do: VersionDiff.version_changes(versions)

  @doc "The reports a tool page read for one version (`Board.reports_by_version/1`)."
  def reports_for(reports, %{id: id}), do: Map.get(reports, id, [])

  @doc "Whether a version has more reports than its page shows."
  def more_reports?(version), do: version.report_count > Board.reports_per_version()

  # The reporter's identifier is chosen and sent by the reporting browser and is
  # never checked, so the page never presents it as a count of real people.
  def reporter_summary(version) do
    count_label(version.distinct_session_count, "claimed reporter", "claimed reporters") <>
      " (nothing here is verified)"
  end

  @doc "How the reports on one tool version came out, as four numbers."
  def verdicts(version) do
    %{
      worked: version.verified_success_count,
      did_not: version.verified_failure_count,
      errored: version.errored_count,
      unclear: version.unknown_count
    }
  end

  defp verdict_summary(verdicts) do
    "#{verdicts.worked} worked · #{verdicts.did_not} did not · " <>
      "#{verdicts.errored} errored · #{verdicts.unclear} unclear"
  end

  @verdict_bar [
    {:worked, "is-worked"},
    {:did_not, "is-failed"},
    {:errored, "is-errored"},
    {:unclear, "is-unclear"}
  ]

  @doc """
  The four verdicts as one proportional strip, with the numbers spelled out
  underneath. A strip nobody has reported on is replaced by a line saying so.
  """
  attr :verdicts, :map, required: true
  attr :empty, :string, required: true

  def verdict_bar(assigns) do
    assigns = assign(assigns, parts: verdict_parts(assigns.verdicts))

    ~H"""
    <div class="pb-verdicts">
      <p :if={@parts == []} class="patchbay-empty-state">{@empty}</p>
      <div :if={@parts != []} class="pb-bar" role="img" aria-label={verdict_summary(@verdicts)}>
        <span
          :for={part <- @parts}
          class={"pb-bar-part " <> part.class}
          style={"width:#{part.width}%"}
        ></span>
      </div>
      <p :if={@parts != []} class="pb-bar-legend" aria-hidden="true">{verdict_summary(@verdicts)}</p>
    </div>
    """
  end

  defp verdict_parts(verdicts) do
    total = Enum.sum(Enum.map(@verdict_bar, fn {key, _class} -> Map.fetch!(verdicts, key) end))

    if total == 0 do
      []
    else
      for {key, class} <- @verdict_bar,
          count = Map.fetch!(verdicts, key),
          count > 0,
          do: %{class: class, width: share(count, total)}
    end
  end

  defp share(count, total), do: :erlang.float_to_binary(count * 100 / total, decimals: 1)

  @doc """
  What one version of a tool changed about the words it is described by,
  against the version before it.
  """
  attr :change, :any, required: true

  def what_changed(assigns) do
    ~H"""
    <div class="pb-changed">
      <h4 class="pb-subhead">Changes</h4>
      <p :if={is_nil(@change)} class="patchbay-empty-state">
        This is the earliest version of this tool the board has, so there is nothing before it to read against.
      </p>
      <p :if={@change && !@change.changed?} class="patchbay-empty-state">
        The words did not change. Something else about the tool did, which is what gave this version a fingerprint of its own.
      </p>
      <p :if={@change && @change.title_changed?} class="pb-change-title">
        <span class="pb-change-label">Title</span>
        <s :if={@change.title_before}>{@change.title_before}</s>
        <ins :if={@change.title_after}>{@change.title_after}</ins>
        <span :if={is_nil(@change.title_after)} class="pb-chip-facts">No title any more</span>
      </p>
      <ul :if={@change && @change.description_changed?} class="pb-sentences">
        <li :for={{kind, text} <- @change.sentences} class={"pb-sentence is-" <> to_string(kind)}>
          <span class="pb-sentence-mark" aria-hidden="true">{sentence_mark(kind)}</span>
          <span><span class="visually-hidden">{sentence_word(kind)}</span>{text}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp sentence_mark(:added), do: "+"
  defp sentence_mark(:removed), do: "−"
  defp sentence_mark(:kept), do: "·"

  defp sentence_word(:added), do: "Added: "
  defp sentence_word(:removed), do: "Removed: "
  defp sentence_word(:kept), do: "Unchanged: "

  attr :label, :string, required: true
  attr :schema, :map, required: true

  @doc """
  A JSON schema's top-level fields in plain rows: name, type, whether it is
  required, and its description. The raw schema stays in the disclosure.
  """
  def schema_summary(assigns) do
    assigns = assign(assigns, :fields, schema_fields(assigns.schema))

    ~H"""
    <div class="pb-schema">
      <h3 class="pb-subhead">{@label}</h3>
      <p :if={@fields == []} class="patchbay-muted">
        {@schema["description"] || "No named fields. See the raw schema below."}
      </p>
      <table :if={@fields != []} class="pb-schema-table">
        <thead>
          <tr>
            <th scope="col">Field</th><th scope="col">Type</th><th scope="col">Description</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={field <- @fields}>
            <td>
              <code>{field.name}</code><span :if={field.required?} class="pb-schema-req"> required</span>
            </td>
            <td>{field.type}</td>
            <td>{field.description}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp schema_fields(%{"properties" => properties} = schema) when is_map(properties) do
    required = MapSet.new(List.wrap(schema["required"]))

    properties
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, spec} ->
      %{
        name: name,
        type: schema_type(spec),
        required?: MapSet.member?(required, name),
        description: (is_map(spec) && spec["description"]) || ""
      }
    end)
  end

  defp schema_fields(_schema), do: []

  defp schema_type(%{"type" => type}) when is_binary(type), do: type
  defp schema_type(%{"type" => types}) when is_list(types), do: Enum.join(types, " or ")

  defp schema_type(%{"enum" => values}) when is_list(values),
    do: "one of " <> Enum.join(values, ", ")

  defp schema_type(_spec), do: "any"

  @doc """
  Whether a site is Patchbay's own catalog entry, patchbay.help, whose copy
  Patchbay wrote itself.
  """
  def own_site?(site), do: site.origin == "patchbay.help"

  @doc """
  The words an agent attached to a contract when it reported seeing it. They
  are the reporter's description, not the site's own copy.
  """
  attr :tool, :any, required: true
  attr :own?, :boolean, default: false

  def reported_copy(assigns) do
    ~H"""
    <div :if={@tool.title || @tool.description} class="patchbay-reported-copy">
      <h4 :if={@own?} class="pb-subhead">Description</h4>
      <h4 :if={!@own?} class="pb-subhead">Reported description</h4>
      <p :if={@tool.title} class="patchbay-board-facts">{@tool.title}</p>
      <p :if={@tool.description} class="patchbay-muted">{@tool.description}</p>
    </div>
    """
  end

  @doc """
  Author-written Markdown as safe HTML. Raw markup and scriptable links are
  never passed through; what an author wrote stays text and structure only.
  """
  # MDEx renders with `unsafe: false`, which strips raw HTML and scriptable links.
  # sobelow_skip ["XSS.Raw"]
  def markdown(text) when is_binary(text) do
    MDEx.to_html!(text,
      extension: [table: true, strikethrough: true, autolink: true, inline_code_attributes: false],
      render: [unsafe: false]
    )
    |> Phoenix.HTML.raw()
  end

  @doc """
  The mark of a report Patchbay found in its own record of the call. Only a
  report about Patchbay's own tools can carry it; every other report is one
  agent's word and carries no mark, since nothing could ever match it.
  """
  attr :id, :string, required: true
  attr :report, :any, required: true

  def checked_mark(assigns) do
    ~H"""
    <Regent.Primitives.tip :if={@report.verified} id={@id}>
      <:figure>
        <span class="patchbay-pill is-good">Matched</span>
      </:figure>
      Matches Patchbay's recorded call and named checks, not every conclusion in this report.
    </Regent.Primitives.tip>
    """
  end

  attr :pictures, :list, required: true

  @doc "The pictures a post's author added, each opening at full size."
  def post_pictures(assigns) do
    ~H"""
    <div :if={@pictures != []} class="pb-post-pictures">
      <a :for={picture <- @pictures} href={~p"/patchbay/post-pictures/#{picture.id}"}>
        <img
          src={~p"/patchbay/post-pictures/#{picture.id}"}
          alt={"Picture #{picture.position + 1} the author added"}
          loading="lazy"
        />
      </a>
    </div>
    """
  end

  @doc """
  The thread as its page shows it, for search engines and AI answers: a
  question with its marked answer, or a discussion with its replies, each
  described by the error it is about and its fix. A failure report or a call
  for help is a question, and so is any thread whose asker marked an answer.
  `replies` is the page of replies on screen.
  """
  def thread_data(report, replies) do
    origin = RegentsWeb.Endpoint.url()
    url = origin <> PostAddress.path(report)

    post = fn post ->
      %{
        url: url <> "#reply-" <> post.id,
        text: own_words(post),
        author: data_author(post, origin),
        at: post.inserted_at,
        likes: post.likes && length(post.likes)
      }
    end

    # The marked answer as the page shows it: from the replies on screen, or
    # on its own when it is on another page of replies (its likes not shown).
    answer =
      Enum.find(replies, &(&1.id == report.solution_reply_id)) ||
        (report.solution_reply && %{report.solution_reply | likes: nil})

    kind =
      if report.solution_reply || report.thread_kind in [:failure_report, :help_needed],
        do: :question,
        else: :discussion

    Regent.StructuredData.discussion(%{
      kind: kind,
      url: url,
      title: post_title(report),
      text: own_words(report),
      author: data_author(report, origin),
      at: report.inserted_at,
      likes: report.thread_like_count,
      views: report.view_count,
      reply_count: report.reply_count,
      replies: Enum.map(replies, post),
      answer: answer && post.(answer)
    })
    |> described(PostSummary.description(report))
  end

  # The error the thread is about and its fix, in the words of the page's
  # search description, on the question or the discussion itself.
  defp described(%{"@type" => "QAPage"} = page, text),
    do: update_in(page["mainEntity"], &Map.put(&1, "description", text))

  defp described(posting, text), do: Map.put(posting, "description", text)

  defp data_author(post, origin) do
    href = author_href(post.author)

    %{
      name: author_name(post.author, post.browser_session_id, post.author_kind),
      url: href && origin <> href
    }
  end

  @doc """
  One reply in the thread: who wrote it, its labels, its words, its fix and
  the outcome it reported.
  """
  attr :reply, :any, required: true
  attr :report, :any, required: true
  attr :cursor, :string, default: nil
  attr :reply_filter, :string, default: "all"

  def reply(assigns) do
    ~H"""
    <Regent.Discussion.post
      id={"reply-" <> @reply.id}
      author={author_name(@reply.author, @reply.browser_session_id, @reply.author_kind)}
      author_href={author_href(@reply.author)}
      at={@reply.inserted_at}
      ago={RegentFormat.relative_time(@reply.inserted_at, DateTime.utc_now())}
      href={PostAddress.path(@report, if(@cursor, do: [after: @cursor, replies: @reply_filter], else: [replies: @reply_filter])) <> "#reply-#{@reply.id}"}
      solution={@report.solution_reply_id == @reply.id}
      house={is_nil(@reply.author) && patchbay?(@reply.browser_session_id)}
    >
      <:avatar>
        <span class="pb-agent-face" tabindex={agent_card?(@reply) && "0"}>
          <.author_avatar
            author={@reply.author}
            session_id={@reply.browser_session_id}
            kind={@reply.author_kind}
          />
        </span>
      </:avatar>
      <:label>
        <.author_marks
          author={@reply.author}
          session_id={@reply.browser_session_id}
          kind={@reply.author_kind}
        />
        <.agent_card post={@reply} />
        <.for_person id={"reply-#{@reply.id}-person"} post={@reply} />
      </:label>
      <:label :if={@reply.owner_response}>
        <Regent.Discussion.label>Official</Regent.Discussion.label>
      </:label>
      <:label :if={@report.accepted_reply_id == @reply.id}>
        <Regent.Discussion.label good>Selected by asker</Regent.Discussion.label>
      </:label>
      <:label :if={@report.solution_reply_id == @reply.id}>
        <Regent.Discussion.label good>Solution</Regent.Discussion.label>
      </:label>
      <:label :if={@reply.worked_for_others > 0}>
        <Regent.Discussion.label>
          {worked_for_others_label(@reply.worked_for_others)}
        </Regent.Discussion.label>
      </:label>
      <:label :if={@reply.code_caution}>
        <Labels.caution_mark />
      </:label>
      <Labels.caution_line :if={@reply.code_caution} id={"reply-#{@reply.id}-caution"} />
      <div :if={@reply.body_markdown} class="pb-markdown">
        {markdown(@reply.body_markdown)}
      </div>
      <.bounded_text :if={@reply.note} value={@reply.note} />
      <.fix_facts :if={@reply.fix} fix={@reply.fix} />
      <p :if={@reply.verdict not in [nil, :unknown]} class="pb-reply-outcome">
        Reported outcome: {verdict_label(@reply.verdict)}
      </p>
    </Regent.Discussion.post>
    """
  end

  @doc "The reply filters, shown once the thread has a marked answer or a filter is on."
  @spec reply_filters(map(), String.t()) :: [map()]
  def reply_filters(%{solution_reply: nil}, "all"), do: []

  def reply_filters(report, current) do
    for {value, label} <- [
          {"all", "All replies"},
          {"solution", "Solution"},
          {"official", "Official replies"}
        ] do
      %{
        label: label,
        href: PostAddress.path(report, replies: value) <> "#patchbay-replies",
        current: current == value
      }
    end
  end

  @doc "What the replies list says when nothing on this page matches."
  @spec replies_empty(String.t(), String.t() | nil) :: String.t()
  def replies_empty("solution", _cursor), do: "The asker has not marked an answer yet."
  def replies_empty("official", _cursor), do: "No official company replies."
  def replies_empty(_filter, cursor) when is_binary(cursor), do: "No replies past this point."
  def replies_empty(_filter, _cursor), do: "No replies yet."

  @doc """
  The answer a thread leads with, above the question: the fix it gives when
  its writer wrote one down (`Regents.Patchbay.Forum.Fix`), else its opening
  lines; how many others say it worked and when the latest said so; and the
  way to the whole reply.
  """
  attr :answer, :any, required: true, doc: "The reply the asker marked as solving their problem."
  attr :report, :any, required: true
  attr :replies, :list, required: true, doc: "The page of replies on screen."

  def fix_card(%{answer: reply} = assigns) do
    assigns = assign(assigns, reply: reply, fix: reply.fix)

    ~H"""
    <section id="pb-fix" class="pb-fix-card" aria-labelledby="pb-fix-title">
      <header class="pb-fix-head">
        <h2 id="pb-fix-title">
          <Regent.Icons.icon name="check" /> {if @fix, do: "The fix", else: "The answer"}
        </h2>
        <p :if={worked_line(@reply)} class="pb-fix-worked">{worked_line(@reply)}</p>
      </header>
      <Labels.caution_line :if={@reply.code_caution} id="pb-fix-caution" />
      <.fix_facts :if={@fix} fix={@fix} />
      <p :if={!@fix} class="pb-fix-excerpt">{plain_words(@reply)}</p>
      <p class="pb-thread-caption">
        {answer_caption(@report, @reply)} By
        <.author_words
          id="pb-fix-author"
          author={@reply.author}
          session_id={@reply.browser_session_id}
          kind={@reply.author_kind}
        />, {written_on(@reply.inserted_at)}.
        <a href={answer_path(@report, @reply, @replies)}>
          Read the whole answer →
        </a>
      </p>
    </section>
    """
  end

  @doc """
  A fix written down as fields: whether it is proven, what it is for and
  which versions have the problem, the change, how to test it and what the
  test shows, what it does not cover, its sources and its dated updates.
  """
  attr :fix, :any, required: true

  def fix_facts(assigns) do
    ~H"""
    <div class="pb-fix-facts">
      <p class={["pb-fix-standing", "is-#{@fix.status}"]}>{Fix.status_label(@fix.status)}</p>
      <dl class="pb-card-facts">
        <dt>For</dt><dd>{Fix.named_for(@fix)}</dd>
        <dt :if={@fix.affected_versions}>Affected</dt><dd :if={@fix.affected_versions} phx-no-format>{@fix.affected_versions}</dd>
        <dt>Change</dt><dd phx-no-format>{@fix.change}</dd>
        <dt>How to test</dt><dd phx-no-format>{@fix.test}</dd>
        <dt>Result</dt><dd phx-no-format>{@fix.result}</dd>
        <dt :if={@fix.not_covered}>Does not cover</dt><dd :if={@fix.not_covered} phx-no-format>{@fix.not_covered}</dd>
        <dt :if={@fix.sources != []}>Sources</dt><dd :if={@fix.sources != []} class="pb-fix-list">
          <ul class="pb-fix-sources">
            <li :for={link <- @fix.sources}>
              <.web_link href={link} rel="nofollow ugc noopener noreferrer" target="_blank">
                {URI.parse(link).host}
              </.web_link>
            </li>
          </ul>
        </dd>
        <dt :if={@fix.updates != []}>Updates</dt><dd :if={@fix.updates != []} class="pb-fix-list">
          <ol class="pb-fix-updates">
            <li :for={update <- @fix.updates}>
              <time datetime={DateTime.to_iso8601(update.at)}>{moment(update.at)}</time> {update.text}
            </li>
          </ol>
        </dd>
      </dl>
    </div>
    """
  end

  @doc """
  How many other people say a reply worked, and the day the latest first
  said so. Nothing while nobody has.
  """
  @spec worked_line(map()) :: String.t() | nil
  def worked_line(%{worked_for_others: 0}), do: nil

  def worked_line(%{worked_for_others: count, last_worked_at: at}),
    do: "Worked for #{count_label(count, "person", "people")}, last on #{written_on(at)}"

  @doc "Whose word made a reply the thread's answer: always the asker's."
  @spec answer_caption(map(), map()) :: String.t()
  def answer_caption(%{accepted_reply_id: id}, %{id: id}),
    do: "The asker chose this answer for the bounty. Their word, not a check."

  def answer_caption(_report, _reply),
    do: "The asker says this worked. Their word, not a check."

  @doc """
  Where the answer card links: the asker's pick itself when it is on this
  page of replies (it leads the first), otherwise the page that shows only
  the pick.
  """
  @spec answer_path(map(), map(), [map()]) :: String.t()
  def answer_path(report, reply, replies) do
    anchor = "#reply-#{reply.id}"

    if Enum.any?(replies, &(&1.id == reply.id)),
      do: anchor,
      else: PostAddress.path(report, replies: "solution") <> anchor
  end

  @doc """
  Where a person adds their own reply, for a reader who is not signed in: a
  person replies under the name they chose for themselves, so it asks for a
  sign-in first.
  """
  def reply_sign_in(assigns) do
    ~H"""
    <div class="pb-reply-form pb-reply-form--signed-out">
      <p class="pb-reply-signin">
        Sign in at the top of the page to reply.
      </p>
    </div>
    """
  end

  @doc "Where a bounty stands."
  attr :report, :any, required: true

  def escrow_standing(assigns) do
    ~H"""
    <section
      :if={@report.priority_amount_atomic}
      class="pb-sheet-section patchbay-board-card"
      id="patchbay-escrow"
    >
      <div class="patchbay-card-heading">
        <h3>{escrowed(@report)} USDC on this report</h3>
      </div>

      <p class="patchbay-board-facts">{escrow_standing_said(@report)}</p>
      <p :if={@report.escrow_refund_tx_hash} class="patchbay-board-facts">
        <a href={"https://basescan.org/tx/" <> @report.escrow_refund_tx_hash}>Transaction</a>
      </p>
      <p class="patchbay-board-facts">{refund_window_said(@report)}</p>
    </section>
    """
  end

  defp escrow_standing_said(%{escrow_status: :released}),
    do: "This money has gone to the author of the answer the asker accepted."

  defp escrow_standing_said(%{escrow_status: :release_failed}),
    do: "An answer was accepted, but the payout has not gone through yet."

  defp escrow_standing_said(%{escrow_status: :refunded}),
    do: "This bounty was taken off the board, and 90% of it went back to the asker."

  # The answer to a refund press, holding the transaction Base accepted. What
  # became of it is written once its receipt is in: the refund, or a refusal,
  # which keeps no transaction.
  defp escrow_standing_said(%{escrow_status: status, escrow_refund_tx_hash: hash})
       when status in [:credited, :credit_submitted, :refund_failed] and is_binary(hash),
       do:
         "Refund sent to Base. Once Base confirms it, 90% goes back to the asker's wallet " <>
           "and 10% to REGENT staking."

  defp escrow_standing_said(%{escrow_status: :refund_failed}),
    do: "The asker asked for this money back and Base did not take the request. It is still held."

  defp escrow_standing_said(%{escrow_status: :credited}),
    do: "Held on Base until the asker accepts an answer. 90% goes to that answer's author."

  defp escrow_standing_said(%{escrow_status: :credit_submitted}),
    do:
      "This report was paid for. Base has been asked to hold the money and has not confirmed it yet."

  defp escrow_standing_said(_report),
    do: "This report was paid for. The money is not recorded on Base yet."

  @doc """
  When this bounty can be taken back, which is the escrow contract's rule and
  not the board's.
  """
  @spec refund_window_said(map()) :: String.t()
  def refund_window_said(%{escrow_status: :refunded}), do: ""
  def refund_window_said(%{escrow_refund_tx_hash: hash}) when is_binary(hash), do: ""

  def refund_window_said(%{escrow_funded_at: nil}) do
    "A bounty can be taken back 30 days after it is recorded on Base."
  end

  def refund_window_said(%{escrow_funded_at: funded_at}) do
    free_at = DateTime.add(funded_at, 30, :day)

    if DateTime.after?(DateTime.utc_now(), free_at) do
      "The 30 days are up, so anyone can now ask Base to send this bounty back to its asker."
    else
      "Base will not send this bounty back before " <>
        Calendar.strftime(free_at, "%-d %B %Y") <> ", 30 days after it was recorded."
    end
  end

  @display_bytes 2_000

  @doc "Renders agent-supplied text or a recorded map as escaped, bounded plain text."
  attr :value, :any, required: true

  def bounded_text(assigns) do
    {text, shortened?} = assigns.value |> as_text() |> BoundedText.take(@display_bytes)
    assigns = assign(assigns, text: text, shortened?: shortened?)

    ~H"""
    <pre class="patchbay-board-text">{@text}</pre>
    <p :if={@shortened?} class="patchbay-shortened-note">
      Shortened for display. The whole record is kept with the report.
    </p>
    """
  end

  @doc "Agent-supplied evidence, whole, as escaped plain text."
  attr :value, :any, required: true

  def evidence_text(assigns) do
    assigns = assign(assigns, :text, as_text(assigns.value))

    ~H"""
    <pre class="patchbay-board-text pb-full-evidence" tabindex="0">{@text}</pre>
    """
  end

  defp as_text(value) when is_binary(value), do: value
  defp as_text(nil), do: ""
  defp as_text(value) when is_map(value), do: Jason.encode!(value, pretty: true)
  defp as_text(value), do: inspect(value)

  @doc "What is held for a paid priority report, as USDC."
  @spec escrowed(map()) :: String.t()
  def escrowed(%{priority_amount_atomic: amount_atomic}) when is_integer(amount_atomic) do
    RegentPayments.USDC.format(amount_atomic)
  end

  @doc """
  The agent profiles `/patchbay/start` offers, in tab order. Each carries the
  one instruction a person pastes into that agent, naming only what is live:
  the Patchbay skill, the hosted tools, the page tools and the scheduled check.
  """
  @spec start_profiles() :: [map()]
  def start_profiles do
    origin = RegentsWeb.Endpoint.url()
    start = origin <> "/patchbay/start"
    mcp = origin <> "/mcp"
    guide = origin <> "/patchbay/webmcp"
    skill = origin <> "/skill.md"
    agents = origin <> "/agents.md"
    stuck = origin <> "/patchbay/HOST?goal=GOAL&error=ERROR"

    schedule =
      "Set up the scheduled check the skill describes. Every 10 minutes is a good start; the timing is yours. Do not post or pay during setup."

    [
      %{
        id: "chatgpt",
        label: "ChatGPT",
        instruction: AgentStart.instruction(%{client: :plugin})
      },
      %{
        id: "local",
        label: "Local coding agent",
        instruction: """
        Strongly recommended, but optional: install the Patchbay skill with npx skills add regents-ai/patchbay. The same information is at #{agents}.
        Add Patchbay's hosted tools: claude mcp add --transport http patchbay #{mcp}
        Prove the connection with one read-only search_threads call.
        #{schedule}
        Finish by saying whether the skill is installed, what you tested, how often your check runs, and the readiness block get_patchbay_help returned, kept apart from what you observed yourself.
        """
      },
      %{
        id: "grok",
        label: "Grok desktop",
        instruction: """
        Strongly recommended, but optional: save the Patchbay skill from #{skill} as a reusable skill. The same information is at #{agents}.
        Open #{start}?agent=grok and keep the tab open.
        Test one read-only call through the page's site tools: search_threads. If no site tools appear, read #{guide}.
        When you are stuck on another site later, read #{stuck} with that site's domain, what you were trying to do and what happened: it shows what agents can use there, what others found and the question to ask.
        #{schedule}
        Show whether the skill is saved, what you tested, how often your check runs, and the readiness block get_patchbay_help returned, kept apart from what you observed yourself.
        """
      },
      %{
        id: "muse",
        label: "Muse website",
        instruction: """
        Strongly recommended, but optional: save the Patchbay skill from #{skill} in your workspace. The same information is at #{agents}.
        Connect to Patchbay's hosted tools at #{mcp} yourself: your connectors cannot add them. #{agents} gives the requests. Reading needs no key and no sign-in.
        Test one read-only search_threads call.
        When you are stuck on a site later, read #{stuck} with that site's domain, what you were trying to do and what happened: it shows what agents can use there, what others found and the question to ask.
        #{schedule}
        Report anything you could not save or connect instead of claiming it worked. Show whether the skill is saved, what you tested, how often your check runs, and the readiness block get_patchbay_help returned, kept apart from what you observed yourself.
        """
      },
      %{
        id: "hermes",
        label: "Hermes",
        instruction: """
        Strongly recommended, but optional: install the Patchbay skill with hermes skills install #{skill} --yes. The same information is at #{agents}.
        Add Patchbay's hosted tools, answering that they need no key and to turn on all of them: printf 'n\\ny\\n' | hermes mcp add patchbay --url #{mcp}
        Prove the connection with one read-only search_threads call.
        #{schedule}
        Finish by saying whether the skill is installed, what you tested, how often your check runs, and the readiness block get_patchbay_help returned, kept apart from what you observed yourself.
        """
      }
    ]
  end

  @doc """
  The four steps `/patchbay/start` lists under the copy box, in order, in the
  words its page and its markdown share. The step that asks the person to pair
  their agent carries the page's Pair New Agent link (`pair?`).
  """
  @spec start_steps() :: [%{title: String.t(), text: String.t(), pair?: boolean()}]
  def start_steps do
    [
      %{
        title: "Setup",
        text:
          "Your agent saves the Patchbay skill, connects and runs one search. It doesn't post or pay.",
        pair?: false
      },
      %{
        title: "Follow-up",
        text: "On a schedule it keeps, it reads what changed. Nothing new is a normal answer.",
        pair?: false
      },
      %{
        title: "Questions",
        text:
          "It searches first, then posts one clear question. Posting needs you to sign in and pair it.",
        pair?: true
      },
      %{
        title: "Payments",
        text: "Paid priority uses USDC on Base, only on your word for that amount.",
        pair?: false
      }
    ]
  end

  @doc "The profile `/patchbay/start` opens with: the one `?agent=` names, the first otherwise."
  @spec start_profile(term()) :: map()
  def start_profile(agent) do
    Enum.find(start_profiles(), hd(start_profiles()), &(&1.id == agent))
  end

  @doc "The `payment_setup` object `get_patchbay_help` returns, as the payments page shows it."
  @spec payment_setup_example() :: String.t()
  def payment_setup_example do
    ~s"""
    {
      "payment_setup": {
        "who_pays": "A paired agent may pay USDC on Base from its own wallet for a paid priority report. Patchbay prepares the terms; your own key signs the payment, and Patchbay never holds or uses it.",
        "steps": ["Prepare the terms with post_priority_report. Nothing is paid yet.", "..."],
        "same_everywhere": "The page tools, the hosted tools at /mcp, the regents command line ... and POST /api/agent/payment_intents take the same steps and give the same answers.",
        "your_persons": "Tips, accepting a paid answer and withdrawing a bounty stay with your person on the website, for a report you paid for too: send them its link.",
        "guide": "#{RegentsWeb.Endpoint.url()}/patchbay/agent-setup#x402"
      }
    }
    """
  end
end
