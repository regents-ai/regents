defmodule RegentsWeb.Autolaunch.Prelaunch do
  @moduledoc "Prelaunch HTTP and LiveView admission, before uploads or write-capable mounts. Accounts stay open."
  @behaviour Plug
  import Plug.Conn
  alias Regents.Autolaunch.Prelaunch

  @opens_soon "Autolaunch opens soon."

  @read_events %{
    RegentsWeb.Autolaunch.HomeLive => ~w(filter retry retry_calls load-more),
    RegentsWeb.Autolaunch.AuctionsLive => ~w(retry),
    RegentsWeb.Autolaunch.TokensLive => ~w(retry),
    RegentsWeb.Autolaunch.MarketPageLive =>
      ~w(retry retry_history scrub scrub_now price_handle check_bid),
    RegentsWeb.Autolaunch.PortfolioLive => ~w(refresh),
    # Accounts stay open: the Account page reads its connections again once
    # the browser has connected or disconnected an X account.
    RegentsWeb.Autolaunch.AccountLive => ~w(refresh_x_connections),
    RegentsWeb.Autolaunch.CoveredCallsLive =>
      ~w(refresh sell sell_expiry sell_strike sell_suggested bid bid_expiry bid_strike bid_suggested buy sale mode dismiss_done),
    RegentsWeb.Autolaunch.ExposureLive => ~w(refresh tab leg dismiss_done),
    RegentsWeb.Autolaunch.EarnLive => ~w(refresh dismiss_done),
    RegentsWeb.Autolaunch.UpcomingLive => ~w(filter)
  }

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    # Router path matching decodes segments; the admission check must do so too.
    path = Enum.map(conn.path_info, &URI.decode/1)

    cond do
      not Prelaunch.read_only?() -> conn
      path in [["autolaunch", "create"], ["autolaunch", "agent-business"]] -> refuse(conn, 404)
      open?(conn.method, path) -> conn
      true -> refuse(conn, 503)
    end
  end

  @doc """
  Whether a request with `method` to `path`, its decoded segments, is served in
  read-only mode; the create pages are closed besides. The guides' Agent access
  table asks it of each action's route (`RegentsWeb.Autolaunch.PublicDocuments`).
  """
  def open?(method, path), do: method in ["GET", "HEAD"] or public_quote?(method, path)

  @doc """
  What a request this plug refuses in read-only mode is answered with, in JSON
  with its hint (`RegentsWeb.Autolaunch.ApiError.body/2`). A launch draft save's hosted
  MCP tool, which this plug does not reach, answers the same
  (`Regents.Autolaunch.AgentAccount`).
  """
  def refusal,
    do:
      RegentsWeb.Autolaunch.Refusal.new(:service_unavailable, "prelaunch_read_only", @opens_soon)

  # These POSTs only calculate a quote: a bid's from stored public data,
  # while covered calls are on a covered call's suggested premium from the
  # chain's reference price, and while Earn is on a deposit's or withdrawal's
  # preview. Off, each address is refused like any other POST.
  defp public_quote?("POST", ["api", "v1", "autolaunch", "auctions", _id, "bid-quote"]), do: true

  defp public_quote?("POST", ["api", "v1", "autolaunch", "covered-calls", _symbol, "quote"]),
    do: Regents.Autolaunch.CoveredCalls.Deployment.enabled?()

  # While Earn is on, an agent's preview of a deposit or withdrawal only reads
  # the chain; its steps wait for the site to open like every other.
  defp public_quote?("POST", ["api", "agent", "v1", "autolaunch", "earn", "quote"]),
    do: Regents.Autolaunch.Earn.Catalog.enabled?()

  defp public_quote?(_, _), do: false

  # The response type and body are fixed here (a JSON error or the rendered
  # error page); neither comes from the request.
  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  defp refuse(conn, status) do
    json? =
      match?(["api" | _], conn.path_info) or
        Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json"))

    {type, body} =
      if json? do
        %RegentsWeb.Autolaunch.Refusal{code: code, message: message} = refusal()
        {"application/json", Jason.encode!(RegentsWeb.Autolaunch.ApiError.body(code, message))}
      else
        {"text/html",
         RegentsWeb.ErrorHTML.render("#{status}.html", %{conn: conn})
         |> Phoenix.HTML.Safe.to_iodata()}
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type(type)
    |> send_resp(status, if(conn.method == "HEAD", do: "", else: body))
    |> halt()
  end

  # An old signed LiveView token must not resurrect a create page over the socket.
  # Write-capable LiveComponents are not mounted at all during prelaunch.
  def on_mount(:default, _params, _session, socket) do
    if Prelaunch.read_only?() and
         socket.view in [RegentsWeb.Autolaunch.StocksCreateLive, RegentsWeb.Autolaunch.CreateLive] do
      {:halt, Phoenix.LiveView.redirect(socket, to: "/autolaunch/app")}
    else
      {:cont,
       Phoenix.LiveView.attach_hook(socket, :prelaunch_read_only, :handle_event, &gate_event/3)}
    end
  end

  defp gate_event(event, _params, socket) do
    if not Prelaunch.read_only?() or event in Map.get(@read_events, socket.view, []),
      do: {:cont, socket},
      else: {:halt, socket}
  end
end
