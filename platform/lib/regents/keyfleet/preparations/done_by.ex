defmodule Regents.Keyfleet.Preparations.DoneBy do
  @moduledoc """
  Keeps a read of one of a fleet's logs to what some Keys or one wallet did,
  or what was done to them, when it is asked to: the `keys` argument names
  Keys by number and `wallet` one wallet in lower case. An entry is kept when
  one of its Key fields holds one of those Keys or one of its wallet fields
  holds that wallet. With both arguments nil, everything is kept.

  The options name the entry's fields: `key`, fields holding one Key each;
  `keys`, a field holding several; `wallet`, fields holding a wallet; and
  `member`, a field naming a member as the workspace does, with its Key and
  its wallet (`Regents.Keyfleet.Graph.Event.member/1`). A log names the fields it
  has.
  """
  use Ash.Resource.Preparation

  require Ash.Query

  import Ash.Expr, only: [expr: 1, ref: 1]

  @impl true
  def prepare(query, opts, _context) do
    keys = Ash.Query.get_argument(query, :keys)
    wallet = Ash.Query.get_argument(query, :wallet)

    if keys == nil and wallet == nil,
      do: query,
      else: Ash.Query.filter(query, ^any_of(conditions(opts, keys || [], wallet)))
  end

  defp conditions(opts, keys, wallet) do
    by_key = for field <- List.wrap(opts[:key]), keys != [], do: expr(^ref(field) in ^keys)

    by_keys =
      for field <- List.wrap(opts[:keys]),
          keys != [],
          do: expr(fragment("? && ?", ^ref(field), type(^keys, {:array, :integer})))

    by_wallet = for field <- List.wrap(opts[:wallet]), wallet, do: expr(^ref(field) == ^wallet)

    by_member =
      for field <- List.wrap(opts[:member]),
          pattern <- member_patterns(keys, wallet),
          do: expr(fragment("? ~ ?", ^ref(field), ^pattern))

    by_key ++ by_keys ++ by_wallet ++ by_member
  end

  # A member is `member:<chain>:<contract>:<Key>@<epoch>/<human or agent>:<wallet>`.
  defp member_patterns(keys, wallet) do
    by_key =
      if keys != [],
        do: ["^member:[0-9]+:0x[0-9a-f]{40}:(#{Enum.join(keys, "|")})@"],
        else: []

    by_key ++ if(wallet, do: ["/(human|agent):#{wallet}$"], else: [])
  end

  defp any_of([]), do: false
  defp any_of([first | rest]), do: Enum.reduce(rest, first, &expr(^&2 or ^&1))
end
