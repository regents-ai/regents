defmodule Regents.Keyfleet.Graph.Writer do
  @moduledoc """
  The single writer for one fleet's work graph.

  Each writer owns one graph host, a Python process behind a port that speaks
  length-prefixed JSON, and sends it one request at a time. The writer outlives
  its host: a host that cannot start, exits, or misses a deadline is replaced
  after a delay that doubles with each failure in a row, and requests made
  while no host is ready return `{:error, :unavailable}`. The first failure in
  a row is saved with the site's errors (`Regents.Keyfleet.Graph.StalledError`).

  A reply that does not arrive within the deadline, or a host that exits while
  a request is in flight, leaves the outcome unknown: the caller gets
  `{:error, :indeterminate}` and the host is killed. The host keeps a ledger of
  every command it committed, so retrying with the same command id returns the
  original result instead of applying it twice. A write can also be checked
  without being made (`check/4`), which the host neither applies nor records.

  Each host is started with the fleet's starting goals (`:starting_goals`, each
  `%{title, outcome}`), which it keeps in the workspace as listed before it
  answers.

  A write's authority is decided at its turn, inside the writer: whatever
  changed while it waited behind other requests, such as a key changing hands,
  counts. That check gets `:check_timeout` to read what it needs, and a caller
  waits for it on top of the reply.

  Each writer is found by its fleet in the `Regents.Keyfleet.Graph.Processes` registry
  of the machine it runs on. The site machine reaches the graph machine's
  writers through `Regents.Keyfleet.Graph.Client`.
  """
  use GenServer

  require Logger

  alias Regents.Keyfleet.Graph.Authority
  alias Regents.Keyfleet.Graph.StalledError

  @read_ops ~w(hello changes)
  @write_ops ~w(create patch link unlink archive join leave submit review fork)

  # How long a killed host gets to be reaped before the writer moves on.
  @reap_ms 5_000

  @hello Jason.encode!(%{v: 1, op: "hello", body: %{}})

  # The same refusal the host gives a frame it cannot parse.
  @unencodable %{
    "code" => "bad_request",
    "message" => "the request cannot be written as JSON",
    "details" => %{}
  }

  # The host inherits nothing from the application's environment: it needs no
  # secrets, and its interpreter runs isolated from PYTHON* variables, the
  # user site directory and the working directory.
  @host_env [{~c"LANG", ~c"C.UTF-8"}]

  @type reply :: {:ok, map()} | {:error, map() | :indeterminate | :unavailable | Exception.t()}

  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :fleet_id)}, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: name(Keyword.fetch!(opts, :fleet_id)))

  defp name(fleet_id),
    do: {:via, Registry, {Regents.Keyfleet.Graph.Processes, {__MODULE__, fleet_id}}}

  @doc "The operations that write, which `command/4` and `check/4` take."
  @spec write_ops() :: [String.t()]
  def write_ops, do: @write_ops

  @doc """
  Sends a read of the log itself (`hello` or `changes`) to the fleet's graph.

  Only the projector reads the log this way, to copy it into the read tables
  every workspace read is answered from; see `Regents.Keyfleet.Graph.Projection`.
  """
  @spec request(String.t(), String.t(), map()) :: reply()
  def request(fleet_id, op, body) when op in @read_ops do
    with {:ok, json} <- encode(%{v: 1, op: op, body: body}) do
      send_to_writer(fleet_id, {:send, json})
    end
  end

  @doc """
  Sends a write to the fleet's graph on behalf of a member.

  `authority` names the rule that decides it (`Regents.Keyfleet.Graph.Authority`),
  run inside the writer when the write's turn comes, just before the write
  reaches the host, with `:check_timeout` to spend. The rule answers the
  command, its `:id`, `:principal`, `:auth` and the fleet's `:projects` as
  they stand at that moment, or a refusal, which is returned as it is with
  nothing sent; a rule that exits or raises is answered `{:error,
  :unavailable}`, also with nothing sent.
  """
  @spec command(String.t(), String.t(), term(), Authority.t()) :: reply()
  def command(fleet_id, op, body, authority) when op in @write_ops do
    with {:ok, json} <- encode(body) do
      send_to_writer(fleet_id, {:command, op, json, authority})
    end
  end

  @doc """
  Checks a write without making it: it takes its turn and is authorized as
  `command/4` would be, and the host decides it as it would decide the write,
  answering `{:ok, reply}` when it would take it, or the refusal the write
  would get. The host writes nothing for a check and keeps no record of its
  command id, so the write itself may follow under the same id.
  """
  @spec check(String.t(), String.t(), term(), Authority.t()) :: reply()
  def check(fleet_id, op, body, authority) when op in @write_ops do
    with {:ok, json} <- encode(body) do
      send_to_writer(fleet_id, {:check, op, json, authority})
    end
  end

  @doc """
  A write's body as JSON, or the refusal the host gives a frame it cannot
  parse. Bodies are encoded in the caller's process, so one that JSON cannot
  express is refused before it reaches the writer.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, map()}
  def encode(term) do
    with {:error, _reason} <- Jason.encode(term), do: {:error, @unencodable}
  end

  defp send_to_writer(fleet_id, request), do: call_writer(name(fleet_id), request, call_timeout())

  @doc """
  The longest a caller waits for a writer: the longest it spends on one
  request once it is that request's turn, a killed host's reaping, and a
  second more.
  """
  @spec call_timeout() :: pos_integer()
  def call_timeout do
    graph = Application.fetch_env!(:regents, :keyfleet_graph)

    Keyword.fetch!(graph, :check_timeout) + Keyword.fetch!(graph, :reply_timeout) + @reap_ms +
      1_000
  end

  # A writer that is not running has done nothing; one that does not answer
  # in time may yet run the request.
  defp call_writer(name, request, timeout) do
    GenServer.call(name, request, timeout)
  catch
    :exit, {:noproc, _} -> {:error, :unavailable}
    :exit, _reason -> {:error, :indeterminate}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      fleet_id: Keyword.fetch!(opts, :fleet_id),
      data_dir: Keyword.fetch!(opts, :data_dir),
      python: Keyword.fetch!(opts, :python),
      reply_timeout: Keyword.fetch!(opts, :reply_timeout),
      check_timeout: Keyword.fetch!(opts, :check_timeout),
      hello_timeout: Keyword.fetch!(opts, :hello_timeout),
      restart_min: Keyword.fetch!(opts, :restart_min),
      restart_max: Keyword.fetch!(opts, :restart_max),
      restart_delay: Keyword.fetch!(opts, :restart_min),
      starting_goals: Jason.encode!(Keyword.fetch!(opts, :starting_goals)),
      host: nil,
      next_req: 0
    }

    {:ok, state, {:continue, :start_host}}
  end

  @impl true
  def handle_continue(:start_host, state), do: {:noreply, start_host(state)}

  @impl true
  def handle_call({:send, json}, _from, %{host: %{ready?: true}} = state) do
    case exchange(json, state) do
      {:ok, reply, state} -> {:reply, reply, state}
      {:lost, reason, state} -> {:reply, {:error, :indeterminate}, host_failed(state, reason)}
    end
  end

  def handle_call({:command, op, body, authority}, from, %{host: %{ready?: true}} = state),
    do: send_command(%{v: 1, op: op}, body, authority, from, state)

  # A check is the write's own frame, marked `check`.
  def handle_call({:check, op, body, authority}, from, %{host: %{ready?: true}} = state),
    do: send_command(%{v: 1, op: op, check: true}, body, authority, from, state)

  def handle_call(_request, _from, state), do: {:reply, {:error, :unavailable}, state}

  defp send_command(message, body, authority, from, state) do
    case stamp(authority, state) do
      {:ok, command} ->
        message = Map.merge(message, %{command: command, body: Jason.Fragment.new(body)})
        handle_call({:send, Jason.encode!(message)}, from, state)

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  # A database pool that is down or out of time exits its caller, and a fault
  # in the ownership check raises; either would stop the writer, so an
  # ownership check that exits or raises is answered as unavailable, with
  # nothing sent.
  defp stamp(authority, state) do
    Authority.command(authority, state.fleet_id, state.check_timeout)
  rescue
    error ->
      Logger.warning(
        "graph write for #{state.fleet_id} not sent: its ownership check raised: " <>
          Exception.message(error)
      )

      {:error, :unavailable}
  catch
    :exit, reason ->
      Logger.warning(
        "graph write for #{state.fleet_id} not sent: its ownership check exited: " <>
          Exception.format_exit(reason)
      )

      {:error, :unavailable}
  end

  @impl true
  def handle_info(:start_host, state), do: {:noreply, start_host(state)}

  def handle_info({port, {:data, data}}, %{host: %{port: port, ready?: false} = host} = state) do
    {req, deadline} = host.hello
    Process.cancel_timer(deadline)

    case decode(data, req) do
      {:ok, _hello} ->
        {:noreply,
         %{state | host: %{host | ready?: true, hello: nil}, restart_delay: state.restart_min}}

      _unexpected ->
        {:noreply, host_failed(state, kill(host, :bad_hello))}
    end
  end

  def handle_info({:hello_deadline, port}, %{host: %{port: port, ready?: false} = host} = state) do
    {:noreply, host_failed(state, kill(host, :hello_timeout))}
  end

  def handle_info({port, {:exit_status, status}}, %{host: %{port: port}} = state) do
    {:noreply, host_failed(state, {:host_exited, status})}
  end

  def handle_info({:EXIT, port, reason}, %{host: %{port: port}} = state) do
    {:noreply, host_failed(state, {:port_closed, reason})}
  end

  # What is left comes from a host this writer has already replaced.
  def handle_info({port, _message}, state) when is_port(port), do: {:noreply, state}
  def handle_info({:EXIT, port, _reason}, state) when is_port(port), do: {:noreply, state}
  def handle_info({:hello_deadline, _port}, state), do: {:noreply, state}
  # A process a write's check linked to the writer, such as a task its reads
  # ran in, has finished.
  def handle_info({:EXIT, pid, _reason}, state) when is_pid(pid), do: {:noreply, state}

  # sobelow_skip ["Traversal.FileModule"]
  defp start_host(state) do
    with :ok <- File.mkdir_p(state.data_dir),
         {:ok, port} <- open_port(state) do
      req = Integer.to_string(state.next_req)
      send(port, {self(), {:command, frame(@hello, req)}})
      deadline = Process.send_after(self(), {:hello_deadline, port}, state.hello_timeout)
      host = %{port: port, ready?: false, hello: {req, deadline}}
      %{state | host: host, next_req: state.next_req + 1}
    else
      {:error, reason} -> host_failed(state, {:start_failed, reason})
    end
  end

  defp open_port(state) do
    db = Path.join(state.data_dir, "#{state.fleet_id}.sqlite")

    args = [
      "-I",
      "-m",
      "keyfleet_graph",
      "--fleet",
      state.fleet_id,
      "--db",
      db,
      "--starting-goals",
      state.starting_goals
    ]

    {:ok,
     Port.open({:spawn_executable, state.python}, [
       :binary,
       :exit_status,
       {:packet, 4},
       {:cd, "/"},
       {:env, host_env()},
       {:args, args}
     ])}
  rescue
    # A missing or unrunnable interpreter.
    error in ErlangError -> {:error, error.original}
  end

  defp host_env do
    inherited = for {name, _value} <- System.get_env(), do: {String.to_charlist(name), false}
    names = Enum.map(@host_env, &elem(&1, 0))
    Enum.reject(inherited, fn {name, false} -> name in names end) ++ @host_env
  end

  # Puts the request id first in an encoded message object. The id is a
  # decimal integer, so it needs no escaping.
  defp frame("{" <> fields, req), do: [~s({"req":"), req, ~s(",), fields]

  defp exchange(json, %{host: %{port: port} = host} = state) do
    req = Integer.to_string(state.next_req)
    send(port, {self(), {:command, frame(json, req)}})
    state = %{state | next_req: state.next_req + 1}

    receive do
      {^port, {:data, data}} ->
        case decode(data, req) do
          :garbled -> {:lost, kill(host, :garbled_reply), state}
          reply -> {:ok, reply, state}
        end

      {^port, {:exit_status, status}} ->
        {:lost, {:host_exited, status}, state}

      {:EXIT, ^port, reason} ->
        {:lost, {:port_closed, reason}, state}
    after
      state.reply_timeout -> {:lost, kill(host, :reply_timeout), state}
    end
  end

  # Replies are strictly in order, so the only reply that may carry no request
  # id is the refusal of a frame the host could not parse at all.
  defp decode(data, req) do
    case Jason.decode(data) do
      {:ok, %{"req" => ^req, "ok" => true} = reply} ->
        {:ok, reply}

      {:ok, %{"req" => reply_req, "ok" => false, "error" => error}}
      when reply_req in [req, nil] ->
        {:error, error}

      _other ->
        :garbled
    end
  end

  # The runtime image has /bin/sh but no kill executable, so the shell's
  # builtin sends the signal. The pid is read from the port just before the
  # signal: the port closes the moment its host is reaped, and a pid is only
  # free for reuse after that. A closed port is left alone, and the one window
  # left, while the shell starts, is far too short for the OS to hand the pid
  # to another process. The host's exit status arrives either way.
  defp kill(%{port: port}, reason) do
    os_pid = signal(port)

    receive do
      {^port, {:exit_status, _status}} -> reason
    after
      @reap_ms ->
        send(port, {self(), :close})
        {reason, {:not_reaped, os_pid}}
    end
  end

  # sobelow_skip ["CI.System"]
  defp signal(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        System.cmd("/bin/sh", ["-c", ~s(kill -9 "$0"), Integer.to_string(os_pid)],
          stderr_to_stdout: true
        )

        os_pid

      nil ->
        nil
    end
  end

  defp host_failed(state, reason) do
    Logger.warning("graph host for #{state.fleet_id} stopped: #{inspect(reason)}")

    if state.restart_delay == state.restart_min,
      do: StalledError.report("The graph host of #{state.fleet_id} stopped: #{inspect(reason)}")

    if state.host && state.host.hello, do: Process.cancel_timer(elem(state.host.hello, 1))

    Process.send_after(self(), :start_host, state.restart_delay)
    %{state | host: nil, restart_delay: min(state.restart_delay * 2, state.restart_max)}
  end
end
