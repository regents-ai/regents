defmodule Regents.Keyfleet.Graph.Pass do
  @moduledoc """
  The pass every request from the site to the graph machine carries, as
  `Authorization: Bearer`: an ES256 JWT signed with the notebook hubs' keys
  (`Regents.Keyfleet.Notebooks.Pass.sign/2`), for the audience `keyfleet-graph`, with
  `sub` `keyfleet`. `fleet` names the one fleet it is for and `scope` the one
  request it allows: `write`, `check` or `await`. It lasts the graph's
  `:pass_ttl_seconds`, and a new one is made for every request.

  The graph machine checks it against the public half of the same keys
  (`Regents.Keyfleet.Notebooks.Pass.verify/2`), which both machines hold.
  """

  alias Regents.Keyfleet.Notebooks.Pass

  @audience "keyfleet-graph"

  @doc "A pass for one request of `scope` to the fleet's graph."
  @spec mint(String.t(), String.t()) :: String.t()
  def mint(fleet_id, scope) do
    Pass.sign(
      %{"aud" => @audience, "sub" => "keyfleet", "fleet" => fleet_id, "scope" => scope},
      Keyword.fetch!(Application.fetch_env!(:regents, :keyfleet_graph), :pass_ttl_seconds)
    )
  end

  @doc "Whether `token` is a pass for one request of `scope` to the fleet's graph."
  @spec valid?(String.t(), String.t(), String.t()) :: boolean()
  def valid?(token, fleet_id, scope) do
    match?(
      {:ok, %{"sub" => "keyfleet", "fleet" => ^fleet_id, "scope" => ^scope}},
      Pass.verify(token, @audience)
    )
  end
end
