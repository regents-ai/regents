defmodule RegentsWeb.Patchbay.SiteRefreshLive do
  @moduledoc """
  A site's picture on its page, with "Refresh this site": any visitor may ask
  for a new picture of the site and a new check of its WebMCP tools, once
  the last picture is a day old (`RegentsWeb.Patchbay.Forum.SiteChecks.refresh/3`).
  The button stays in view when it can't be pressed, with when it can be
  again. The picture and the words change when the new picture, or the
  check, comes back.
  """

  use RegentsWeb, :live_view

  import RegentsWeb.Patchbay.Forum.BoardHTML,
    only: [moment: 1, site_domain: 1, site_screenshot_url: 1]

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.Site
  alias Regents.Patchbay.Forum.SiteCheck
  alias RegentsWeb.Patchbay.Forum.SiteChecks

  @impl true
  def mount(_params, %{"origin" => origin, "visitor" => visitor}, socket) do
    if connected?(socket) do
      :ok = Phoenix.PubSub.subscribe(Regents.PubSub, SiteCheck.topic(origin))
      :ok = Phoenix.PubSub.subscribe(Regents.PubSub, "patchbay:site_picture:" <> origin)
    end

    # Drawn with the page, the panel takes the site and check the page has
    # just read (`assign_new/3` finds them in the page's assigns); a live
    # connection reads them itself.
    {:ok,
     socket
     |> assign(origin: origin, visitor: visitor, limited?: false)
     |> assign_new(:site, fn -> read_site(origin) end)
     |> assign_new(:check, fn -> read_check(origin) end)
     |> then(&assign_state(&1, &1.assigns.site, &1.assigns.check)), layout: false}
  end

  @impl true
  def handle_info(%Ash.Notifier.Notification{resource: SiteCheck, data: check}, socket),
    do: {:noreply, assign_state(socket, read_site(socket.assigns.origin), check)}

  def handle_info(%Ash.Notifier.Notification{resource: Site}, socket),
    do: {:noreply, assign_state(socket, read_site(socket.assigns.origin), socket.assigns.check)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # Whether the site may be refreshed is read again here, never taken from
  # the page.
  @impl true
  def handle_event("refresh", _params, socket) do
    %{origin: origin, visitor: visitor} = socket.assigns

    case read_site(origin) do
      %Site{} = site ->
        {answer, check} = SiteChecks.refresh(site, read_check(origin), visitor)
        {:noreply, socket |> assign(limited?: answer == :limited) |> assign_state(site, check)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp read_site(origin) do
    case Forum.get_site_by_origin(origin, load: [:refresh_due?]) do
      {:ok, site} -> site
      _ -> nil
    end
  end

  defp read_check(origin) do
    case SiteChecks.current(origin) do
      {:ok, check} -> check
      _ -> nil
    end
  end

  defp assign_state(socket, nil, check),
    do: assign(socket, site: nil, check: check, state: :unavailable, now: DateTime.utc_now())

  defp assign_state(socket, site, check) do
    assign(socket,
      site: site,
      check: check,
      state: SiteChecks.refresh_state(site, check),
      now: DateTime.utc_now()
    )
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shot_url, assigns.site && site_screenshot_url(assigns.site))

    ~H"""
    <figure :if={@shot_url} class="pb-entry-shot">
      <img
        src={@shot_url}
        alt={"Screenshot of " <> site_domain(@site)}
        width="1600"
        height="1000"
        loading="lazy"
        decoding="async"
      />
    </figure>
    <p :if={@site} class="pb-site-refresh">
      <button
        type="button"
        class="pb-quiet-button"
        phx-click="refresh"
        disabled={@state != :ready}
      >
        Refresh this site
      </button>
      <span role="status">
        <.refresh_words state={@state} site={@site} now={@now} />
      </span>
    </p>
    <p :if={@limited?} class="pb-site-refresh-note" role="alert">
      You've refreshed a lot of sites just now. Try again in a few minutes.
    </p>
    """
  end

  attr(:state, :any, required: true)
  attr(:site, :map, required: true)
  attr(:now, DateTime, required: true)

  defp refresh_words(%{state: :refreshing} = assigns),
    do: ~H"Taking a new picture and checking its tools…"

  defp refresh_words(%{state: {:fresh, at}} = assigns) do
    assigns = assign(assigns, at: at, again: again_words(at, assigns.now))

    ~H"""
    Refreshed <.ago at={@at} now={@now} /> · again {@again}
    """
  end

  defp refresh_words(
         %{state: :ready, site: %{screenshot_captured_at: %DateTime{} = at}} = assigns
       ) do
    assigns = assign(assigns, at: at)
    ~H"Picture taken <.ago at={@at} now={@now} />"
  end

  defp refresh_words(assigns), do: ~H""

  # How long until the site can be refreshed again, rounded up, so the two
  # times add up to a day: "in 21 hours", "in 5 minutes".
  defp again_words(at, now) do
    seconds = max(DateTime.diff(DateTime.shift(at, day: 1), now), 1)

    if seconds >= 3600,
      do: in_words(div(seconds + 3599, 3600), "hour"),
      else: in_words(div(seconds + 59, 60), "minute")
  end

  defp in_words(1, word), do: "in 1 " <> word
  defp in_words(count, word), do: "in #{count} #{word}s"

  attr(:at, DateTime, required: true)
  attr(:now, DateTime, required: true)

  defp ago(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@at)} title={moment(@at)}>{RegentFormat.relative_time(
      @at,
      @now
    )}</time>
    """
  end
end
