defmodule RegentSprites do
  @moduledoc """
  Fly Sprites machines for Regent Elixir apps: create and look up a machine,
  checkpoint and restore its disk, run a command on it, and move files in and out.

  The app sets the token in `config/runtime.exs`:

      config :regent_sprites, token: System.get_env("SPRITES_TOKEN")

  Every call goes to the Sprites API with Req and is tried once; the app decides
  when to try again (an Oban job, for example).
  `config :regent_sprites, :req_options` adds Req options to every call.

  Files move through commands, never through Sprites' file endpoints: after a
  restore those endpoints still show the disk as it was before, while a command
  sees the restored disk. Commands and their arguments travel in the request's
  address, so a secret must never be one; send it as standard input instead.
  """

  alias RegentSprites.{Checkpoint, Error, Output, Sprite}

  @base_url "https://api.sprites.dev"
  @receive_timeout 30_000
  @stream_timeout 300_000
  @write_file ~S(umask 077 && cat > "$1" && chmod "$2" "$1")

  @doc """
  Creates a machine.

  Options:

    * `:url_auth` — who may open the machine's web address: `"sprite"` (members of
      the organization, the default) or `"public"`
    * `:wait_for_capacity` — whether Sprites holds the request until there is room

  A name already in use answers `{:sprites, 409, message}`.
  """
  @spec create(String.t(), keyword()) :: {:ok, Sprite.t()} | {:error, Error.t()}
  def create(name, opts \\ []) when is_binary(name) do
    body =
      %{name: name, url_settings: %{auth: Keyword.get(opts, :url_auth, "sprite")}}
      |> put_present(:wait_for_capacity, opts[:wait_for_capacity])

    with {:ok, body} <- request(:post, "/v1/sprites", [json: body], 201) do
      sprite(body)
    end
  end

  @doc "Looks up a machine by name. An unknown name answers `{:sprites, 404, message}`."
  @spec get(String.t()) :: {:ok, Sprite.t()} | {:error, Error.t()}
  def get(name) when is_binary(name) do
    with {:ok, body} <- request(:get, sprite_path(name), [], 200) do
      sprite(body)
    end
  end

  @doc "Deletes a machine and every checkpoint it has."
  @spec delete(String.t()) :: :ok | {:error, Error.t()}
  def delete(name) when is_binary(name) do
    with {:ok, _body} <- request(:delete, sprite_path(name), [], 204), do: :ok
  end

  @doc """
  Saves the machine's disk as a checkpoint and returns it.

  The comment is the checkpoint's key. If a checkpoint already has it, that one is
  returned and nothing new is made, so a job that runs twice makes one checkpoint.
  """
  @spec checkpoint(String.t(), String.t()) :: {:ok, Checkpoint.t()} | {:error, Error.t()}
  def checkpoint(name, comment) when is_binary(name) and is_binary(comment) and comment != "" do
    with {:ok, checkpoints} <- checkpoints(name) do
      case with_comment(checkpoints, comment) do
        [] -> make_checkpoint(name, comment)
        [checkpoint] -> {:ok, checkpoint}
        _many -> {:error, %Error{reason: {:comment_not_unique, comment}}}
      end
    end
  end

  @doc "Lists the machine's checkpoints, including `\"Current\"`, the live disk."
  @spec checkpoints(String.t()) :: {:ok, [Checkpoint.t()]} | {:error, Error.t()}
  def checkpoints(name) when is_binary(name) do
    with {:ok, body} <- request(:get, sprite_path(name) <> "/checkpoints", [], 200) do
      parse_all(body, &Checkpoint.from_api/1)
    end
  end

  @doc """
  Restores the machine's disk to a checkpoint.

  Sprites has refused a restore made moments after a checkpoint, answering
  `{:stream, message}`; the app decides whether to try again.
  """
  @spec restore(String.t(), String.t()) :: :ok | {:error, Error.t()}
  def restore(name, checkpoint_id) when is_binary(name) and is_binary(checkpoint_id) do
    path = sprite_path(name) <> "/checkpoints/" <> URI.encode(checkpoint_id) <> "/restore"

    with {:ok, body} <- request(:post, path, stream_options(), 200) do
      finished(body)
    end
  end

  @doc """
  Runs a command on the machine and returns what it printed and its exit code.

  `argv` is the program and its arguments, run without a shell. A non-zero exit code
  is a result, not an error. Options:

    * `:stdin` — bytes sent to the command's standard input
    * `:dir` — the working directory
    * `:receive_timeout` — milliseconds to wait for the command to end, 30,000 by default
  """
  @spec exec(String.t(), [String.t(), ...], keyword()) :: {:ok, Output.t()} | {:error, Error.t()}
  def exec(name, [_program | _args] = argv, opts \\ []) when is_binary(name) do
    query =
      Enum.map(argv, &{"cmd", &1}) ++
        if(opts[:dir], do: [{"dir", opts[:dir]}], else: []) ++
        if(opts[:stdin], do: [{"stdin", "true"}], else: [])

    path = sprite_path(name) <> "/exec?" <> URI.encode_query(query, :rfc3986)

    options =
      [
        decode_body: false,
        receive_timeout: Keyword.get(opts, :receive_timeout, @receive_timeout)
      ] ++ stdin_options(opts[:stdin])

    with {:ok, body} <- request(:post, path, options, 200) do
      case Output.from_frames(body) do
        {:ok, output} -> {:ok, output}
        :error -> unexpected()
      end
    end
  end

  @doc """
  Reads a file from the machine, as the restored disk holds it.

  The file travels as base64, so any bytes come back exactly. Takes `exec/3`'s
  `:receive_timeout`.
  """
  @spec read_file(String.t(), String.t(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def read_file(name, path, opts \\ []) when is_binary(path) do
    with {:ok, %Output{exit_code: 0, stdout: stdout}} <-
           exec(name, ["base64", "-w0", "--", path], Keyword.take(opts, [:receive_timeout])) do
      case Base.decode64(stdout) do
        {:ok, content} -> {:ok, content}
        :error -> unexpected()
      end
    else
      {:ok, %Output{exit_code: code, stderr: stderr}} ->
        {:error, %Error{reason: {:exit, code, stderr}}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Writes a file on the machine, readable only by its owner while it is written.

  Options: `:mode`, the file's final permissions (`"600"` by default), and `exec/3`'s
  `:receive_timeout`.
  """
  @spec write_file(String.t(), String.t(), binary(), keyword()) :: :ok | {:error, Error.t()}
  def write_file(name, path, content, opts \\ []) when is_binary(path) and is_binary(content) do
    argv = ["sh", "-c", @write_file, "sh", path, Keyword.get(opts, :mode, "600")]

    case exec(name, argv, [stdin: content] ++ Keyword.take(opts, [:receive_timeout])) do
      {:ok, %Output{exit_code: 0}} ->
        :ok

      {:ok, %Output{exit_code: code, stderr: stderr}} ->
        {:error, %Error{reason: {:exit, code, stderr}}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp make_checkpoint(name, comment) do
    options = [json: %{comment: comment}] ++ stream_options()

    with {:ok, body} <- request(:post, sprite_path(name) <> "/checkpoint", options, 200),
         :ok <- finished(body),
         {:ok, checkpoints} <- checkpoints(name) do
      case with_comment(checkpoints, comment) do
        [checkpoint] -> {:ok, checkpoint}
        [] -> {:error, %Error{reason: {:checkpoint_not_found, comment}}}
        _many -> {:error, %Error{reason: {:comment_not_unique, comment}}}
      end
    end
  end

  defp with_comment(checkpoints, comment), do: Enum.filter(checkpoints, &(&1.comment == comment))

  # A checkpoint or restore answers one JSON object per line and finishes with a
  # `complete` line; an `error` line means it failed, whatever came before.
  defp finished(body) do
    with {:ok, events} <- decode_lines(body) do
      cond do
        message = Enum.find_value(events, &error_message/1) ->
          {:error, %Error{reason: {:stream, message}}}

        Enum.any?(events, &match?(%{"type" => "complete"}, &1)) ->
          :ok

        true ->
          {:error, %Error{reason: :stream_incomplete}}
      end
    end
  end

  defp decode_lines(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, events} ->
      case Jason.decode(line) do
        {:ok, %{"type" => type} = event} when is_binary(type) -> {:cont, {:ok, [event | events]}}
        _other -> {:halt, unexpected()}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      {:error, error} -> {:error, error}
    end
  end

  defp error_message(%{"type" => "error", "error" => message}) when is_binary(message),
    do: message

  defp error_message(%{"type" => "error"}), do: "no message"
  defp error_message(_event), do: nil

  defp sprite(body) do
    case Sprite.from_api(body) do
      {:ok, sprite} -> {:ok, sprite}
      :error -> unexpected()
    end
  end

  defp parse_all(items, parse) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, parsed} ->
      case parse.(item) do
        {:ok, value} -> {:cont, {:ok, [value | parsed]}}
        :error -> {:halt, unexpected()}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, error} -> {:error, error}
    end
  end

  defp parse_all(_body, _parse), do: unexpected()

  defp request(method, path, options, expected_status) do
    with {:ok, token} <- token() do
      [
        method: method,
        url: @base_url <> path,
        auth: {:bearer, token},
        retry: false,
        receive_timeout: @receive_timeout
      ]
      |> Keyword.merge(options)
      |> Keyword.merge(Application.get_env(:regent_sprites, :req_options, []))
      |> Req.request()
      |> answer(expected_status)
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}, status), do: {:ok, body}

  defp answer({:ok, %Req.Response{status: status, body: body}}, _expected) do
    {:error, %Error{reason: {:sprites, status, error_text(body)}}}
  end

  defp answer({:error, exception}, _expected) do
    {:error, %Error{reason: {:transport, Exception.message(exception)}}}
  end

  defp error_text(%{"error" => message}) when is_binary(message), do: message
  defp error_text(_body), do: nil

  defp token do
    case Application.get_env(:regent_sprites, :token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _missing -> {:error, %Error{reason: :token_missing}}
    end
  end

  defp stream_options, do: [decode_body: false, receive_timeout: @stream_timeout]

  defp stdin_options(nil), do: []

  defp stdin_options(stdin) when is_binary(stdin) do
    [body: stdin, headers: [{"content-type", "application/octet-stream"}]]
  end

  defp sprite_path(name), do: "/v1/sprites/" <> URI.encode(name, &URI.char_unreserved?/1)

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp unexpected, do: {:error, %Error{reason: :unexpected_response}}
end
