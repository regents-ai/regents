defmodule Regents.Patchbay do
  @moduledoc """
  Patchbay's core, folded in from patchbay.help one slice at a time
  (`SOURCE.json` beside this module names what came from where). So far it holds
  what the pages that need no database read, all from files committed under
  `priv/patchbay`: About, the Terms of Use and the agent guide
  (`WrittenPages`), the changelog (`Changelog`), the tool manifest
  (`Forum.Capabilities`) and the words-with-addresses cutter (`AddressText`).

  Its tables, in the `patchbay_app` schema, are carried as resources in six
  domains (`Forum`, `Members`, `Assist`, `AnswerWatch`, `Messages`, `Offers`):
  every attribute, relationship and identity as patchbay.help has them, no
  action yet and one policy refusing every action, so nothing here reads or
  writes a row.
  """
  use Boundary,
    top_level?: true,
    deps: [Regents],
    exports: [AddressText, Changelog, Forum.Capabilities, WrittenPages]

  @doc "`:ok`: nothing Patchbay serves yet reads anything that could be unavailable."
  def health, do: :ok

  @doc """
  Whether payments are on here, as the payments page says: people can sign in
  (the site's Privy app is set) and Base can be read for balances
  (`RegentPayments.Balance.configured?/0`).
  """
  @spec payments_enabled?() :: boolean()
  def payments_enabled? do
    case Application.get_env(:regents, :privy, [])[:app_id] do
      id when is_binary(id) and id != "" -> RegentPayments.Balance.configured?()
      _unset -> false
    end
  end
end
