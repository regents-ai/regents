defmodule RegentsWeb.EventInput do
  @moduledoc """
  What a page sends, read before any of it is kept. Each field a handler names
  is text no longer than its limit; a field that is anything else refuses the
  whole event, so the handler never assigns a map, a list or a megabyte string.
  Each page keeps its own limits and its own meaning for the text.
  """

  @failure_reasons ~w(step_unknown wallet_unavailable network_mismatch wallet_declined insufficient_funds send_unconfirmed)

  @doc "A reason the page gives for a wallet press that sent nothing, or may have sent something."
  defguard failure_reason(reason) when reason in @failure_reasons

  @doc """
  The named fields of `params` that are present, each as bounded text:
  `{:ok, %{field => text}}`, or `:error` when `params` is not a map or any named
  field is not text within its limit. A field the page did not send stays out.
  """
  def texts(params, limits) when is_map(params) do
    Enum.reduce_while(limits, {:ok, %{}}, fn {field, limit}, {:ok, read} ->
      case Map.fetch(params, field) do
        {:ok, text} when is_binary(text) and byte_size(text) <= limit ->
          {:cont, {:ok, Map.put(read, field, text)}}

        {:ok, _unreadable} ->
          {:halt, :error}

        :error ->
          {:cont, {:ok, read}}
      end
    end)
  end

  def texts(_params, _limits), do: :error

  @doc "What a page says when something it sent could not be read."
  def unreadable, do: "That couldn’t be read, so nothing changed."
end
