defmodule Regents.Keyfleet.Notebooks.Files do
  @moduledoc """
  A fleet's notebooks and their files, that an agent creates, lists, reads
  and writes through its own signed requests to this site
  (`RegentsWeb.Keyfleet.AgentNotebookController`), so it never signs a request for
  the notebook host itself. The hub is asked as the agent
  (`Regents.Keyfleet.Notebooks.MemberRequest`), so each notebook and each change is
  the agent's.

  A notebook's files sit beside its code, `notebook.py`, which its runs and
  sessions see. Writing `notebook.py` or `pyproject.toml` saves a new version
  of the notebook. Adding a file never replaces one, so many writers can each
  add files of their own to one notebook without losing any, and only a
  file's maker writes over it.

  Each file read and each file saved answers its `revision`, the hub's ETag
  for the stored file. Writing over a file names the revision it was read
  at, and the hub stores the write only while the file still has it, so a
  write over a change made since is refused, never applied.

  Each answer is `{:ok, answer}` or `{:error, reason}`: `:file_not_found` for a
  notebook or file the hub doesn't have; `{:stale_revision, revision}` when
  the file was changed since the revision written over was read, with the
  file's revision now; `:file_exists` when another file, or a
  folder, is at the path written, or a file is where one of its folders would
  be; `:writes_paused` when the notebook is open for editing or saving another
  change; `:not_maker` for writing over another member's file; `:refused` for a
  path or file the hub doesn't take; `:cursor_unknown` for a listing's cursor
  the hub doesn't take; `:files_full` when the notebook holds as
  much as it takes; `:too_large` or `:not_text` for a file this site doesn't
  read out; `:unknown` when the hub was asked to write a file and its answer
  can't be read, so the file may be written; or `:unavailable` when the hub
  didn't answer and nothing was written.
  """

  import Regents.Keyfleet.Notebooks.MemberRequest

  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.Makers

  # A file read out here is text, at most this many bytes.
  @read_max_bytes 1024 * 1024
  # A listing names at most this many entries a page.
  @page 200
  # What a run ran from is read in one page of the hub's largest.
  @manifest_page 500
  # Connecting to the hub failed in these ways, so it was never asked.
  @unreached [:econnrefused, :nxdomain, :ehostunreach, :enetunreach]
  # The hub's strong ETag for a stored file; its quoted value is the revision.
  @etag ~r/\A"([!#-~]{1,128})"\z/

  @doc """
  Makes a notebook titled `title` with `code` as `subject`, answering its id,
  title and address (`Regents.Keyfleet.Notebooks.notebook_url/3`). Once the hub has
  answered, the same `idempotency_key` answers that notebook again; one sent
  while the first is still being made can make a second.
  """
  def create(fleet_id, subject, project_id, notebook, idempotency_key) do
    fleet_id
    |> request(subject, :post, "/api/v1/projects/#{segment(project_id)}/notebooks",
      json: Map.put_new(notebook, "description", ""),
      headers: [{"idempotency-key", idempotency_key}]
    )
    |> answer(201)
    |> case do
      {:ok, %{"id" => id, "title" => title}} ->
        {:ok,
         %{
           notebook_id: id,
           title: title,
           notebook_url: Notebooks.notebook_url(fleet_id, project_id, id)
         }}

      error ->
        error
    end
  end

  @doc """
  The entries of the folder `path` in `notebook_id`, as `subject`: a page
  of them, the `cursor` that names the next page, or nil after the last, and
  `has_more`, whether there is one. A later page the hub refuses is
  `:cursor_unknown`: the folder was taken for the page that gave the cursor.
  """
  def list(fleet_id, subject, project_id, notebook_id, path, cursor) do
    params = [path: path, cursor: cursor, limit: @page] |> Enum.reject(&is_nil(elem(&1, 1)))

    fleet_id
    |> request(
      subject,
      :get,
      notebook_path(project_id, notebook_id) <> "/workspace/entries",
      params: params
    )
    |> answer(200)
    |> case do
      {:ok, %{"items" => items} = page} ->
        next = page["cursor"]
        {:ok, %{entries: Enum.map(items, &entry/1), cursor: next, has_more: next != nil}}

      {:error, :refused} when is_binary(cursor) ->
        {:error, :cursor_unknown}

      refused ->
        refused
    end
  end

  @doc """
  Every file of `notebook_id`, at any depth, as `subject`, each as `%{path,
  size, revision}` with the revision a read of it answers (nil when the hub
  names none), read in one page of at most #{@manifest_page} files; and
  `complete`, whether that page held every file. Files in a `__marimo__`
  folder at any depth are left out: marimo writes them itself when a
  notebook runs or is open (saved pages, session caches), so they are not
  what a run ran from.
  """
  def manifest(fleet_id, subject, project_id, notebook_id) do
    with {:ok, %{"items" => items} = page} <-
           fleet_id
           |> request(
             subject,
             :get,
             notebook_path(project_id, notebook_id) <> "/workspace/entries",
             params: [recursive: true, limit: @manifest_page]
           )
           |> answer(200) do
      files =
        for %{"path" => path} = item <- items, not marimo_owned?(path) do
          %{path: path, size: item["size"], revision: listed_revision(item["etag"])}
        end

      {:ok, %{files: files, complete: page["cursor"] == nil}}
    end
  end

  defp marimo_owned?(path), do: "__marimo__" in String.split(path, "/")

  defp listed_revision(etag) when is_binary(etag) do
    case Regex.run(@etag, etag) do
      [_etag, revision] -> revision
      nil -> nil
    end
  end

  defp listed_revision(_none), do: nil

  @doc """
  The text of the file at `path` in `notebook_id`, as `subject`, with its
  `sha256` (`sha256/1`) and the `revision` it was read at, from the same
  read of the hub's store.
  """
  def read(fleet_id, subject, project_id, notebook_id, path) do
    case request(
           fleet_id,
           subject,
           :get,
           notebook_path(project_id, notebook_id) <> "/workspace/files",
           params: [path: path],
           compressed: false,
           into: &read_capped/2
         ) do
      {:ok, %Req.Response{status: 200, body: :too_large}} ->
        {:error, :too_large}

      {:ok, %Req.Response{status: 200, body: content} = response} when is_binary(content) ->
        if String.valid?(content), do: text(path, content, response), else: {:error, :not_text}

      response ->
        answer(response, 200)
    end
  end

  defp text(path, content, response) do
    with {:ok, revision} <- revision(response),
         do: {:ok, %{path: path, content: content, sha256: sha256(content), revision: revision}}
  end

  @doc "The sha256 of `content`, in lowercase hex, as a file read answers it."
  def sha256(content), do: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)

  @doc """
  Writes `content` to the file at `path` in `notebook_id`, as `subject`,
  making its folders as needed: `:add` makes a new file, kept as
  `subject`'s, and leaves one already there as it is, answering
  `:file_exists`; `{:write, revision}` replaces a file `subject` made, or
  any file of a notebook open to `actor` for editing
  (`Regents.Keyfleet.Notebooks.Makers.open_to?/4`), answering `:not_maker` for anyone
  else's, and only while the file is still at `revision`: one changed since
  answers `{:stale_revision, revision}` with its revision now, and is never
  written again here. Either answers the file saved with its new `revision`.
  A file added whose maker can't be kept is removed again, so it never stays
  as the notebook maker's.

  The hub refuses either with one conflict for every reason, so the path is
  read to tell them apart: an add's own file saved before is that add's
  answer; another file there, a folder with something in it, or a file where
  one of its folders would be, is `:file_exists`; with none of those, writes
  are paused (`:writes_paused`), as an empty folder at the path reads too.
  """
  def write(fleet_id, _actor, subject, project_id, notebook_id, path, content, :add) do
    with {:ok, key} <- file_key(path),
         {:ok, item} <- add(fleet_id, subject, project_id, notebook_id, path, key, content),
         :ok <- Makers.record_added(fleet_id, subject, project_id, notebook_id, key),
         do: {:ok, item}
  end

  def write(fleet_id, actor, subject, project_id, notebook_id, path, content, {:write, revision}) do
    with {:ok, key} <- file_key(path) do
      case overwrite(fleet_id, actor, subject, project_id, notebook_id, key) do
        :ok -> replace(fleet_id, subject, project_id, notebook_id, path, key, content, revision)
        {:error, :not_found} -> {:error, :file_not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp add(fleet_id, subject, project_id, notebook_id, path, key, content) do
    case put(fleet_id, subject, project_id, notebook_id, path, content, :create) do
      {:error, :conflict} -> taken(fleet_id, subject, project_id, notebook_id, path, key, content)
      answer -> answer
    end
  end

  # The hub's store retries a save whose answer it lost, and its retry then
  # finds the file the first try saved and answers conflict. A conflict on a
  # file that holds exactly what was sent, and that no one else made, is this
  # add's own file, saved; while that can't be read, the add may be saved.
  defp taken(fleet_id, subject, project_id, notebook_id, path, key, content) do
    case read(fleet_id, subject, project_id, notebook_id, path) do
      {:ok, %{content: ^content} = file} -> own(fleet_id, subject, notebook_id, key, file)
      {:ok, _another} -> {:error, :file_exists}
      {:error, reason} when reason in [:too_large, :not_text] -> {:error, :file_exists}
      {:error, :file_not_found} -> paused(fleet_id, subject, project_id, notebook_id, key)
      {:error, _unread} -> {:error, :unknown}
    end
  end

  defp own(fleet_id, subject, notebook_id, key, file) do
    case Makers.unclaimed?(fleet_id, notebook_id, key, subject) do
      {:ok, true} ->
        {:ok,
         %{
           path: "/" <> key,
           kind: "file",
           size: byte_size(file.content),
           modified_at: nil,
           revision: file.revision
         }}

      {:ok, false} ->
        {:error, :file_exists}

      {:error, :unavailable} ->
        {:error, :unknown}
    end
  end

  defp replace(fleet_id, subject, project_id, notebook_id, path, key, content, revision) do
    with {:error, :conflict} <-
           put(fleet_id, subject, project_id, notebook_id, path, content, {:write, revision}),
         do: paused(fleet_id, subject, project_id, notebook_id, key)
  end

  # A conflict with no file at the path: a folder with something in it is
  # there, or a file where one of its folders would be, or else the notebook
  # is open for editing or saving another change.
  defp paused(fleet_id, subject, project_id, notebook_id, key) do
    fleet_id
    |> request(subject, :get, notebook_path(project_id, notebook_id) <> "/workspace/entries",
      params: [path: key, limit: 1]
    )
    |> answer(200)
    |> case do
      {:ok, %{"items" => []}} -> folders(fleet_id, subject, project_id, notebook_id, key)
      {:ok, %{"items" => _items}} -> {:error, :file_exists}
      error -> error
    end
  end

  # Each folder the path names, read as a file: one that is a file takes the
  # path; with none, writes are paused.
  defp folders(fleet_id, subject, project_id, notebook_id, key) do
    parts = String.split(key, "/")

    1..(length(parts) - 1)//1
    |> Enum.map(&(parts |> Enum.take(&1) |> Enum.join("/")))
    |> Enum.reduce_while({:error, :writes_paused}, fn folder, paused ->
      case read(fleet_id, subject, project_id, notebook_id, folder) do
        {:error, :file_not_found} -> {:cont, paused}
        {:ok, _file} -> {:halt, {:error, :file_exists}}
        {:error, reason} when reason in [:too_large, :not_text] -> {:halt, {:error, :file_exists}}
        {:error, _unread} -> {:halt, {:error, :unavailable}}
      end
    end)
  end

  defp overwrite(fleet_id, actor, subject, project_id, notebook_id, key) do
    case Makers.open_to?(fleet_id, actor, notebook_id, :edit) do
      {:ok, true} -> :ok
      {:ok, false} -> Makers.overwrite(fleet_id, subject, project_id, notebook_id, key)
      {:error, reason} -> {:error, reason}
    end
  end

  defp file_key(path) do
    with :error <- Makers.file_key(path), do: {:error, :refused}
  end

  # A new file (`:create`), or one written over only while the hub's store
  # still holds it at `revision` (`{:write, revision}`, sent as `If-Match`).
  defp put(fleet_id, subject, project_id, notebook_id, path, content, precondition) do
    {create, condition} =
      case precondition do
        :create -> {true, []}
        {:write, revision} -> {false, [{"if-match", ~s("#{revision}")}]}
      end

    fleet_id
    |> request(subject, :put, notebook_path(project_id, notebook_id) <> "/workspace/files",
      params: [path: path, create: create],
      headers: [{"content-type", "application/octet-stream"} | condition],
      body: content
    )
    |> case do
      {:ok, %Req.Response{status: 409}} ->
        {:error, :conflict}

      # The file changed since `revision`, and nothing was written. With no
      # revision now, the file is gone.
      {:ok, %Req.Response{status: 412} = response} when not create ->
        case revision(response) do
          {:ok, current} -> {:error, {:stale_revision, current}}
          {:error, :unavailable} -> {:error, :file_not_found}
        end

      {:error, %Req.TransportError{reason: reason}} when reason in @unreached ->
        {:error, :unavailable}

      response ->
        written(response, answer(response, 200))
    end
  end

  defp written({:ok, response}, {:ok, item}) do
    case revision(response) do
      {:ok, revision} -> {:ok, item |> entry() |> Map.put(:revision, revision)}
      {:error, :unavailable} -> {:error, :unknown}
    end
  end

  # Asked, with no answer read: the file may be written.
  defp written(_response, {:error, :unavailable}), do: {:error, :unknown}
  defp written(_response, refused), do: refused

  # The revision the hub's answer names for the stored file.
  defp revision(response) do
    with [etag] <- Req.Response.get_header(response, "etag"),
         [_etag, revision] <- Regex.run(@etag, etag) do
      {:ok, revision}
    else
      _none -> {:error, :unavailable}
    end
  end

  defp entry(item) do
    %{
      path: item["path"],
      kind: item["kind"],
      size: item["size"],
      modified_at: item["modified_at"]
    }
  end

  defp read_capped({:data, data}, {request, response}) do
    if byte_size(response.body) + byte_size(data) > @read_max_bytes,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: response.body <> data}}}
  end

  defp answer({:ok, %Req.Response{status: status, body: %{"data" => data}}}, status),
    do: {:ok, data}

  defp answer({:ok, %Req.Response{status: 404}}, _status), do: {:error, :file_not_found}

  defp answer({:ok, %Req.Response{status: status}}, _status) when status in [400, 403, 422],
    do: {:error, :refused}

  defp answer({:ok, %Req.Response{status: status}}, _status) when status in [413, 429],
    do: {:error, :files_full}

  defp answer(_response, _status), do: {:error, :unavailable}
end
