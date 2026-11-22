defmodule Regents.Keyfleet.Graph.Client do
  @moduledoc """
  How the site asks the fleets' writers and projectors for a write, a check or
  an await, with the meanings `Regents.Keyfleet.Graph.Writer` and
  `Regents.Keyfleet.Graph.Projector` give them.

  Where the writers run on this machine (`:graph, :enabled`, which is
  development), it calls them here. In production they run on the graph
  machine, and each call is one request to its private listener
  (`Regents.Keyfleet.Graph.Listener`) at the graph's `:url`, under a pass for that
  fleet and that request alone (`Regents.Keyfleet.Graph.Pass`). Each is made once,
  never retried, on a connection of its own, so one left from before the
  graph machine restarted is never mistaken for an answer that was lost.

  The site machine holds at most 50 of those connections at once, in a pool
  of its own (`child_spec/1`). A fleet's writer answers in milliseconds, so
  50 requests still waiting means the graph machine is not answering; past
  that, a request waits up to a second for a connection and is then not sent.

  A write or check waits as long as the writer may take
  (`Regents.Keyfleet.Graph.Writer.call_timeout/0`) and a second more. When the
  listener has no address or refuses the connection, every connection is in
  use, or the listener refuses the request, nothing was written: `{:error,
  :unavailable}`. When no answer came back once the request was sent, within
  the wait, or no connection was made within a second, the write may yet
  have been made: `{:error, :indeterminate}`, and sending the same command id
  again either answers it or makes it once. An await that cannot be answered
  is 0. Each request that was not sent, or was refused, is logged.
  """

  require Logger

  alias Regents.Keyfleet.Graph.Authority
  alias Regents.Keyfleet.Graph.Errors.EditsRestrictedError
  alias Regents.Keyfleet.Graph.Errors.NotKeyHolderError
  alias Regents.Keyfleet.Graph.Pass
  alias Regents.Keyfleet.Graph.Projector
  alias Regents.Keyfleet.Graph.Writer
  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError

  @pool_size 50

  # How long a request waits for one of the pool's connections to be free.
  @pool_wait_ms 1_000

  # How long reaching the listener may take. A stopped graph machine has no
  # address and one starting refuses the connection, both at once, and
  # nothing is sent: `:unavailable`. A connection not made in this time ends
  # in a timeout, which cannot be told from an answer that did not come in
  # time, so its outcome is unknown: `:indeterminate`.
  @connect_ms 1_000

  # Errors that leave the request unsent.
  @unsent [:econnrefused, :nxdomain, :ehostunreach, :enetunreach, :eaddrnotavail]

  # How Finch begins the error it raises when no connection was free in time.
  @pool_full "Finch was unable to provide a connection"

  @doc "The site machine's connections to the graph machine."
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Finch.child_spec(
      name: __MODULE__,
      pools: %{
        default: [
          size: @pool_size,
          # The graph process group's private name has only an IPv6 record,
          # so only IPv6 is tried: after any IPv6 failure Mint would try IPv4
          # too, and report that attempt's error instead of the real one.
          conn_opts: [transport_opts: [inet6: true, inet4: false, timeout: @connect_ms]]
        ]
      }
    )
  end

  @doc "Sends a write to the fleet's graph; see `Regents.Keyfleet.Graph.Writer.command/4`."
  @spec command(String.t(), String.t(), map(), Authority.t()) :: Writer.reply()
  def command(fleet_id, op, body, authority) do
    if here?(),
      do: Writer.command(fleet_id, op, body, authority),
      else: write("write", fleet_id, op, body, authority)
  end

  @doc "Checks a write without making it; see `Regents.Keyfleet.Graph.Writer.check/4`."
  @spec check(String.t(), String.t(), map(), Authority.t()) :: Writer.reply()
  def check(fleet_id, op, body, authority) do
    if here?(),
      do: Writer.check(fleet_id, op, body, authority),
      else: write("check", fleet_id, op, body, authority)
  end

  @doc "Waits for the fleet's read tables; see `Regents.Keyfleet.Graph.Projector.await/3`."
  @spec await(String.t(), String.t(), non_neg_integer()) :: non_neg_integer()
  def await(fleet_id, run_id, seq) do
    if here?() do
      Projector.await(fleet_id, run_id, seq)
    else
      case post(fleet_id, "await", Jason.encode!(%{run_id: run_id, seq: seq}), Projector.wait()) do
        {:ok, %{"watermark" => watermark}} when is_integer(watermark) and watermark >= 0 ->
          watermark

        _no_answer ->
          0
      end
    end
  end

  defp here?, do: Keyword.fetch!(Application.fetch_env!(:regents, :keyfleet_graph), :enabled)

  defp write(scope, fleet_id, op, body, authority) do
    with {:ok, json} <- Writer.encode(body) do
      request =
        Jason.encode!(%{
          op: op,
          body: Jason.Fragment.new(json),
          authority: Authority.encode(authority)
        })

      case post(fleet_id, scope, request, Writer.call_timeout()) do
        {:ok, %{"answer" => answer} = reply} -> answer(answer, reply, fleet_id)
        {:ok, _no_answer} -> {:error, :indeterminate}
        {:error, _reason} = error -> error
      end
    end
  end

  # The listener's answer, `{:ok, body}`; `{:error, :unavailable}` when the
  # request was not sent or was refused before it ran; otherwise `{:error,
  # :indeterminate}`.
  defp post(fleet_id, scope, json, wait) do
    case request(fleet_id, scope, json, wait) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} when status in 400..499 ->
        unavailable(fleet_id, scope, "refused by the graph machine with status #{status}")

      {:error, %Req.TransportError{reason: reason} = error} when reason in @unsent ->
        unavailable(fleet_id, scope, "not sent: " <> Exception.message(error))

      {:error, :pool_full} ->
        unavailable(fleet_id, scope, "not sent: all #{@pool_size} connections are in use")

      _no_answer ->
        {:error, :indeterminate}
    end
  end

  defp unavailable(fleet_id, scope, what) do
    Logger.warning("graph #{scope} for #{fleet_id} " <> what)
    {:error, :unavailable}
  end

  defp request(fleet_id, scope, json, wait) do
    Req.request(
      method: :post,
      base_url: Keyword.fetch!(Application.fetch_env!(:regents, :keyfleet_graph), :url),
      # A catalog fleet's id, which the relay's `KnownFleet` admitted.
      url: "/fleets/#{fleet_id}/#{scope}",
      auth: {:bearer, Pass.mint(fleet_id, scope)},
      headers: [content_type: "application/json", connection: "close"],
      body: json,
      retry: false,
      redirect: false,
      finch: [name: __MODULE__, pool_timeout: @pool_wait_ms],
      receive_timeout: wait + 1_000
    )
  rescue
    # Finch raises, rather than answers, when no connection is free within
    # `pool_timeout`, and no option makes it answer instead. That error alone,
    # by its message, is a request never sent; any other is raised again.
    error in RuntimeError ->
      if String.starts_with?(error.message, @pool_full),
        do: {:error, :pool_full},
        else: reraise(error, __STACKTRACE__)
  end

  defp answer("ok", %{"reply" => %{} = reply}, _fleet_id), do: {:ok, reply}
  defp answer("refused", %{"refusal" => %{} = refusal}, _fleet_id), do: {:error, refusal}
  defp answer("unavailable", _body, _fleet_id), do: {:error, :unavailable}
  defp answer("indeterminate", _body, _fleet_id), do: {:error, :indeterminate}

  defp answer("not_key_holder", %{"token_id" => token_id}, fleet_id),
    do: {:error, NotKeyHolderError.exception(fleet_id: fleet_id, token_id: token_id)}

  defp answer("edits_restricted", %{"token_id" => token_id}, fleet_id),
    do: {:error, EditsRestrictedError.exception(fleet_id: fleet_id, token_id: token_id)}

  defp answer("ownership_refreshing", _body, fleet_id),
    do: {:error, OwnershipRefreshingError.exception(fleet_id: fleet_id)}

  defp answer(_unknown, _body, _fleet_id), do: {:error, :indeterminate}
end
