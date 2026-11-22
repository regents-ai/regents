defmodule Regents.Patchbay.Incidents.Discussion do
  @moduledoc """
  Each incident's one discussion: an ordinary thread on its software's board
  with the briefing as its opening post, so replies, likes and views work on
  it as they do on any thread. The incidents list counts its replies.
  """

  alias Regents.Patchbay.Forum

  @doc "How many replies each opened, shown discussion has, by incident name."
  @spec reply_counts() :: {:ok, %{String.t() => non_neg_integer()}} | {:error, term()}
  def reply_counts do
    with {:ok, threads} <- Forum.list_incident_discussions(load: [:reply_count]) do
      {:ok, Map.new(threads, &{&1.incident, &1.reply_count})}
    end
  end
end
