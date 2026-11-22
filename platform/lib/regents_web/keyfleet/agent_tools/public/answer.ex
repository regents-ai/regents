defmodule RegentsWeb.Keyfleet.AgentTools.Public.Answer do
  @moduledoc """
  What anyone reads about the fleets without signing in, the same at their
  public addresses and as the Claude connector's tools
  (`RegentsWeb.Keyfleet.AgentTools.Public`): every fleet and one fleet from the
  directory (`:fleets`, `:fleet`, `Regents.Keyfleet.Directory`), an open fleet's
  latest workspace changes (`:pulse`), its proposals (`:proposals`) and its
  treasury (`:treasury`). Each answer is `{status, body, nil}`; `params` is
  the address's names with its query. None of them reads as the caller:
  every caller is answered alike.
  """

  alias Regents.Keyfleet.{Chain, Directory, Fleets, Proposals}
  alias RegentsWeb.Keyfleet.{DirectoryJSON, PageRead, ProposalJSON, ProposalsPage, Refusal}

  @doc "Answers `op`; the caller and the waiter are unused."
  @spec answer(atom(), map(), term(), term()) :: {pos_integer(), map(), nil}
  def answer(:fleets, _params, _actor, _waiter) do
    case directory(&Directory.list/0) do
      {:ok, fleets} -> ok(DirectoryJSON.index(%{fleets: fleets, generated_at: now()}))
      {:error, _failure} -> refusal(503, "directory_unavailable")
    end
  end

  def answer(:fleet, %{"fleet_id" => fleet_id}, _actor, _waiter) do
    case directory(fn -> Directory.fleet(fleet_id) end) do
      {:ok, fleet} -> ok(DirectoryJSON.show(%{fleet: fleet, generated_at: now()}))
      :unknown -> refusal(404, "fleet_unknown")
      {:error, _failure} -> refusal(503, "directory_unavailable")
    end
  end

  def answer(:pulse, %{"fleet_id" => fleet_id} = params, _actor, _waiter) do
    with {:ok, after_seq} <- since(Map.delete(params, "fleet_id")),
         {:ok, pulse} <- Regents.Keyfleet.WorkspacePulse.read(fleet_id, after_seq) do
      ok(pulse)
    else
      :error -> refusal(400, "invalid_pulse_cursor")
      :unknown -> refusal(404, "fleet_unknown")
      {:error, _error} -> refusal(503, "graph_unavailable")
    end
  end

  def answer(:proposals, %{"fleet_id" => fleet_id} = params, _actor, _waiter) do
    with {:ok, before} <- cursor(Map.delete(params, "fleet_id")),
         {:ok, %{} = result} <- PageRead.run("proposals", fn -> listing(fleet_id, before) end) do
      ok(result)
    else
      :error -> refusal(400, "invalid_proposal_cursor")
      {:ok, :unknown} -> refusal(404, "fleet_unknown")
      {:error, _failure} -> refusal(503, "proposals_unavailable")
    end
  end

  # A fleet that isn't open has no treasury to show; one that can't be read
  # is unavailable for now.
  def answer(:treasury, %{"fleet_id" => fleet_id}, _actor, _waiter) do
    case PageRead.run("treasury", fn -> treasury(fleet_id) end) do
      {:ok, nil} -> refusal(404, "fleet_unknown")
      {:ok, page} -> ok(treasury_json(fleet_id, page))
      {:error, _failure} -> refusal(503, "treasury_unavailable")
    end
  end

  defp ok(body), do: {200, body, nil}
  defp refusal(status, code), do: {status, Refusal.body(code), nil}

  # A read that fails outright is unavailable too, like a count that can't be
  # read.
  defp directory(read),
    do: with({:ok, answer} <- PageRead.run("directory", read), do: answer)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp cursor(params) when map_size(params) == 0, do: {:ok, nil}

  defp cursor(%{"before" => value} = params) when map_size(params) == 1 and is_binary(value) do
    if Regex.match?(~r/\A[1-9][0-9]{0,18}\z/, value) and
         String.to_integer(value) <= 9_223_372_036_854_775_807,
       do: {:ok, String.to_integer(value)},
       else: :error
  end

  defp cursor(_params), do: :error

  defp since(params) when map_size(params) == 0, do: {:ok, nil}

  defp since(%{"after" => value} = params) when map_size(params) == 1 and is_binary(value) do
    if Regex.match?(~r/\A(0|[1-9][0-9]{0,18})\z/, value) and
         String.to_integer(value) <= 9_223_372_036_854_775_807,
       do: {:ok, String.to_integer(value)},
       else: :error
  end

  defp since(_params), do: :error

  defp listing(fleet_id, before) do
    if fleet_id in Fleets.open_fleet_ids() do
      fleet = Fleets.get_fleet!(fleet_id)
      {proposals, more?} = Proposals.list_page(fleet_id, before)
      deployed? = fleet.manager_address != nil

      %{
        fleet_id: fleet_id,
        deployed: deployed?,
        catching_up: deployed? and not Chain.fresh?(fleet_id),
        source: "indexed",
        generated_at: DateTime.utc_now(),
        proposals: Enum.map(proposals, &ProposalJSON.list_item/1),
        next_before: if(more?, do: Integer.to_string(List.last(proposals).number)),
        has_more: more?
      }
    else
      :unknown
    end
  end

  defp treasury(fleet_id) do
    if fleet_id in Fleets.open_fleet_ids(),
      do: ProposalsPage.treasury_page(fleet_id)
  end

  defp treasury_json(fleet_id, page) do
    %{
      fleet_id: fleet_id,
      chain_id: page.chain_id,
      catching_up: page.catching_up?,
      deployed: page.deployed?,
      treasury: page.treasury,
      manager_address: page.manager_address,
      manager_explorer: explorer(page.manager_address),
      treasury_explorer: if(page.treasury, do: explorer(page.treasury.address)),
      balance_meaning:
        "held is in the treasury; backed is held separately in the rewards contract",
      permissions: Regents.Keyfleet.Authority.treasury_rows(),
      proposals_url: ProposalsPage.list_path(fleet_id),
      usage: page.usage
    }
  end

  defp explorer(nil), do: nil
  defp explorer(address), do: "https://basescan.org/address/#{address}"
end
