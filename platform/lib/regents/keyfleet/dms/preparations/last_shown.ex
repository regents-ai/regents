defmodule Regents.Keyfleet.Dms.Preparations.LastShown do
  @moduledoc """
  Loads each conversation as the reading Key (`token_id`) sees it (`side/1`):
  its last message, `last_seq`, `last_body`, `last_from_token_id` and
  `last_at`, and its side's `auto_delete_days` (`Regents.Keyfleet.Dms.Conversation`).
  With `newest_first: true`, the conversations come newest message first.
  """
  use Ash.Resource.Preparation

  @side [:last_seq, :last_body, :last_from_token_id, :last_at, :auto_delete_days]

  @doc "What to load of a conversation for Key `token_id`'s view of it."
  def side(token_id), do: Enum.map(@side, &{&1, %{token_id: token_id}})

  @impl true
  def prepare(query, opts, _context) do
    as_key = %{token_id: Ash.Query.get_argument(query, :token_id)}
    query = Ash.Query.load(query, side(as_key.token_id))

    if Keyword.get(opts, :newest_first, false),
      do: Ash.Query.sort(query, [{:last_seq, {as_key, :desc_nils_last}}, id: :asc]),
      else: query
  end
end
