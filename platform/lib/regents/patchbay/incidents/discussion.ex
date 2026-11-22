defmodule Regents.Patchbay.Incidents.Discussion do
  @moduledoc """
  Each incident's one discussion: an ordinary thread on its software's board
  with the briefing as its opening post, so replies, likes and views work on
  it as they do on any thread.

  The file stays the briefing's source: a release that changes it changes the
  opening post the next time the page is read, except where the site only
  reads (`Regents.read_only?/0`), where the post is shown as it is stored.
  """

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Incidents

  @doc """
  The incident's shown discussion, brought up to date with its file if it
  needs to be; nil while it has not been opened.
  """
  @spec current(Incidents.t()) :: {:ok, Ash.Resource.record() | nil} | {:error, term()}
  def current(incident) do
    case Forum.get_incident_discussion(incident.name) do
      {:ok, nil} -> {:ok, nil}
      {:ok, thread} -> briefing(thread, incident)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "How many replies each opened, shown discussion has, by incident name."
  @spec reply_counts() :: {:ok, %{String.t() => non_neg_integer()}} | {:error, term()}
  def reply_counts do
    with {:ok, threads} <- Forum.list_incident_discussions(load: [:reply_count]) do
      {:ok, Map.new(threads, &{&1.incident, &1.reply_count})}
    end
  end

  defp briefing(%{title: title, body_markdown: body} = thread, %{title: title, body: body}),
    do: {:ok, thread}

  defp briefing(thread, incident) do
    if Regents.read_only?(),
      do: {:ok, thread},
      else:
        Forum.refresh_incident_briefing(thread, %{
          title: incident.title,
          body_markdown: incident.body
        })
  end
end
