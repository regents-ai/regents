defmodule RegentsWeb.Keyfleet.AgentWaits do
  @moduledoc """
  How many agent requests are held open waiting for news, from one client
  address and on this machine. Each waiting request process registers under its
  address's limiter key (`RegentsWeb.ClientAddress.key/1`) for as long as it
  holds its request, so a place is given back when the wait ends or its process
  does.
  """

  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: __MODULE__)

  @doc """
  Runs `fun` with whether this request may wait: `true` while its address holds
  no more than `:agent_waits_per_address` waiting requests and the machine no
  more than `:agent_waits_total`, counting this one.
  Registering before counting means two requests arriving together can both be
  told not to wait, never both told to wait past the cap.
  """
  def hold(address, fun) do
    {:ok, _owner} = Registry.register(__MODULE__, address, nil)

    try do
      fun.(
        Registry.count_match(__MODULE__, address, :_) <= per_address() and
          Registry.count(__MODULE__) <= total()
      )
    after
      Registry.unregister(__MODULE__, address)
    end
  end

  defp per_address, do: Application.fetch_env!(:regents, :agent_waits_per_address)
  defp total, do: Application.fetch_env!(:regents, :agent_waits_total)
end
