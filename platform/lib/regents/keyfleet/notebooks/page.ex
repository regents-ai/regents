defmodule Regents.Keyfleet.Notebooks.Page do
  @moduledoc """
  What a kept page holds, read for an agent: its cells, in the page's order,
  from the session marimo writes into the page it exports (`marimo export
  html`; marimo's `NotebookSessionV1`, version "1"). The page defines
  `window.__MARIMO_MOUNT_CONFIG__` as `Object.freeze({...})`, an object marimo
  writes as JSON; that object is decoded, and nothing else of the page is
  read. A page with no such session, or a session of another version, holds
  nothing read here.

  Each cell is `%{id, console, outputs, error}`:

    * `console`, what the cell printed, in order, as `%{name, mimetype, text,
      bytes, cut}`, `name` being "stdout", "stderr" or "media". marimo writes
      the traceback of an exception the cell raised here, on "stderr", as
      `application/vnd.marimo+traceback`, highlighted as HTML.
    * `outputs`, what the cell showed, as `%{mimetype, text, bytes, cut}`, a
      bundle of several values listed value by value, without its display
      hints.
    * `error`, nil, or the first error marimo recorded for the cell:
      `%{kind, message, traceback, cut}`, where `kind` is marimo's name for
      it (such as "exception" or "syntax") and `traceback` is nil unless the
      notebook shows tracebacks.

  `text` is a value as text, JSON for one that isn't a string, and nil for a
  picture, sound, video or PDF (marimo's media types, kept as data URLs);
  `bytes` is the value's size in the page. A text longer than the per-value
  limit is cut there and says `cut`, as does an error whose cell recorded
  more than one. Cells are kept in order while their JSON fits the budget
  and the rest are left out; `truncated` says whether anything was cut or
  left out.
  """

  @mount_config ~s("__MARIMO_MOUNT_CONFIG__")
  # What follows the object in the statement that defines it.
  @statement_end ~r/\)\s*,\s*writable:\s*false,\s*configurable:\s*false,\s*\}\);\s*\z/
  @bundle "application/vnd.marimo+mimebundle"
  @media ["image/", "audio/", "video/", "application/pdf"]

  @doc """
  The cells of `page` that fit in `budget` bytes of JSON, each text cut at
  `value_bytes`: `{:ok, cells, truncated}`, or `{:error, :unreadable}` when
  the page holds no session read here.
  """
  @spec read(binary(), non_neg_integer(), pos_integer()) ::
          {:ok, [map()], boolean()} | {:error, :unreadable}
  def read(page, budget, value_bytes) do
    with {:ok, cells} <- session_cells(page) do
      {kept, left_out?} = fit(cells, value_bytes, budget, [])
      {:ok, kept, left_out? or Enum.any?(kept, &cut?/1)}
    end
  end

  defp session_cells(page) do
    with [_before, rest] <- String.split(page, @mount_config, parts: 2),
         [_define, rest] <- String.split(rest, "Object.freeze(", parts: 2),
         [script | _after] <- String.split(rest, "</script>", parts: 2),
         {:ok, %{"session" => %{"version" => "1", "cells" => cells}}} when is_list(cells) <-
           Jason.decode(Regex.replace(@statement_end, script, "")) do
      {:ok, cells}
    else
      _unreadable -> {:error, :unreadable}
    end
  end

  # Each cell is read only once those before it have fitted, and counts with
  # the comma before it.
  defp fit([cell | rest], value_bytes, room, kept) do
    read = cell(cell, value_bytes)
    size = byte_size(Jason.encode!(read)) + 1

    if size <= room,
      do: fit(rest, value_bytes, room - size, [read | kept]),
      else: {Enum.reverse(kept), true}
  end

  defp fit([], _value_bytes, _room, kept), do: {Enum.reverse(kept), false}

  defp cell(%{"id" => id, "console" => console, "outputs" => outputs}, value_bytes) do
    %{
      id: id,
      console: Enum.map(console, &printed(&1, value_bytes)),
      outputs:
        for(
          %{"type" => "data", "data" => data} <- outputs,
          value <- Enum.flat_map(data, &values/1),
          do: value(value, value_bytes)
        ),
      error: error(for(%{"type" => "error"} = error <- outputs, do: error), value_bytes)
    }
  end

  defp printed(
         %{"type" => "stream", "name" => name, "mimetype" => mimetype, "text" => text},
         value_bytes
       ),
       do: Map.put(value({mimetype, text}, value_bytes), :name, name)

  defp printed(
         %{"type" => "streamMedia", "name" => name, "mimetype" => mimetype, "data" => data},
         value_bytes
       ),
       do: Map.put(value({mimetype, data}, value_bytes), :name, name)

  # marimo writes a bundle as JSON text, or as the object itself.
  defp values({@bundle, bundle}) when is_binary(bundle) do
    case Jason.decode(bundle) do
      {:ok, %{} = values} -> values({@bundle, values})
      _not_an_object -> [{@bundle, bundle}]
    end
  end

  defp values({@bundle, %{} = values}),
    do: values |> Map.delete("__metadata__") |> Enum.flat_map(&values/1)

  defp values(value), do: [value]

  defp value({mimetype, value}, value_bytes) do
    whole = if is_binary(value), do: value, else: Jason.encode!(value)
    {text, cut} = if media?(mimetype), do: {nil, false}, else: cut(whole, value_bytes)
    %{mimetype: mimetype, text: text, bytes: byte_size(whole), cut: cut}
  end

  defp media?(mimetype), do: is_binary(mimetype) and String.starts_with?(mimetype, @media)

  defp error([], _value_bytes), do: nil

  defp error([%{"ename" => kind, "evalue" => message} = first | more], value_bytes) do
    {message, message_cut} = cut(message, value_bytes)
    {traceback, traceback_cut} = traceback(first["traceback"], value_bytes)

    %{
      kind: kind,
      message: message,
      traceback: traceback,
      cut: message_cut or traceback_cut or more != []
    }
  end

  # A traceback marimo writes on the error itself is text; it writes none
  # unless the notebook shows tracebacks.
  defp traceback(traceback, value_bytes) when is_binary(traceback),
    do: cut(traceback, value_bytes)

  defp traceback(_none, _value_bytes), do: {nil, false}

  defp cut(text, value_bytes) when byte_size(text) <= value_bytes, do: {text, false}
  defp cut(text, value_bytes), do: {String.byte_slice(text, 0, value_bytes), true}

  defp cut?(%{console: console, outputs: outputs, error: error}),
    do: Enum.any?(console ++ outputs, & &1.cut) or match?(%{cut: true}, error)
end
