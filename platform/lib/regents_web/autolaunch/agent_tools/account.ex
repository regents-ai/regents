defmodule RegentsWeb.Autolaunch.AgentTools.Account do
  @moduledoc """
  Paired-agent private Autolaunch reads, launch draft saves, Exposure holdings/
  steps, and non-custodial unsigned step builders exposed through the unified
  `/mcp` server.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: RegentsWeb.Autolaunch.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Autolaunch.{
    AgentBid,
    AgentFinish,
    AgentLaunch,
    AgentRobinhoodBid,
    AgentStake,
    Exposure
  }

  alias RegentsWeb.Autolaunch.{AccountAnswer, ApiError, ExposureAnswer, Prelaunch}

  # Text goes to the draft as the route takes it: untrimmed, empty included.
  @text [allow_empty?: true, trim?: false]
  @uint256_max 2 ** 256 - 1

  actions do
    action :revstake_draft, :map do
      allow_nil? true
      run fn _input, %{actor: actor} -> ApiError.data(AccountAnswer.draft("revstake", actor)) end
    end

    action :revstake_draft_save, :map do
      argument :name, :string, constraints: @text
      argument :symbol, :string, constraints: @text
      argument :description, :string, constraints: @text
      argument :website, :string, constraints: @text
      argument :telegram, :string, constraints: @text
      argument :discord, :string, constraints: @text
      argument :other_link_1, :string, constraints: @text
      argument :other_link_2, :string, constraints: @text
      argument :other_link_3, :string, constraints: @text
      argument :treasury, :string, constraints: @text
      argument :treasury_path, :atom, constraints: [one_of: [:safe, :contract, :eoa]]
      argument :image, :map

      run fn input, %{actor: actor} -> __MODULE__.save("revstake", input.arguments, actor) end
    end

    action :memestock_draft, :map do
      allow_nil? true
      run fn _input, %{actor: actor} -> ApiError.data(AccountAnswer.draft("memestock", actor)) end
    end

    action :memestock_draft_save, :map do
      argument :name, :string, constraints: @text
      argument :symbol, :string, constraints: @text
      argument :description, :string, constraints: @text
      argument :website, :string, constraints: @text
      argument :telegram, :string, constraints: @text
      argument :discord, :string, constraints: @text
      argument :other_link_1, :string, constraints: @text
      argument :other_link_2, :string, constraints: @text
      argument :other_link_3, :string, constraints: @text
      argument :chain, :atom, constraints: [one_of: [:base, :robinhood]]
      argument :stock_address, :string, constraints: @text
      argument :image, :map

      run fn input, %{actor: actor} -> __MODULE__.save("memestock", input.arguments, actor) end
    end

    action :my_positions, :map do
      run fn _input, %{actor: actor} -> ApiError.data(AccountAnswer.positions(actor)) end
    end

    action :my_after_hour_stocks, :map do
      argument :series, :string, allow_nil?: false, constraints: [trim?: false]

      run fn %{arguments: %{series: series}}, %{actor: actor} ->
        Exposure.exposure_holdings(series, actor: actor)
        |> ExposureAnswer.answer(:holdings)
        |> ApiError.data()
      end
    end

    action :after_hour_stocks_prepare, :map do
      argument :series, :string, allow_nil?: false, constraints: [trim?: false]

      argument :kind, :atom,
        allow_nil?: false,
        constraints: [one_of: [:buy, :sell, :mint, :redeem, :update, :end]]

      argument :leg, :atom, constraints: [one_of: [:overnight, :session]]
      argument :amount, :integer, constraints: [min: 1, max: @uint256_max]
      argument :overnight, :integer, constraints: [min: 0, max: @uint256_max]
      argument :session, :integer, constraints: [min: 0, max: @uint256_max]
      argument :signer, :string, constraints: [trim?: false]

      run fn %{arguments: args}, %{actor: actor} ->
        if Regents.Autolaunch.Prelaunch.read_only?() do
          {:error, Prelaunch.refusal()}
        else
          extra = args |> Map.drop([:series, :kind]) |> drop_nils()

          Exposure.prepare_exposure(args.series, args.kind, extra, actor: actor)
          |> ExposureAnswer.answer(:prepare)
          |> ApiError.data()
        end
      end
    end

    action :bid_prepare, :map do
      argument :auction_id, :uuid, allow_nil?: false
      argument :amount, :string, allow_nil?: false, constraints: @text
      argument :max_price, :string, allow_nil?: false, constraints: @text
      argument :pay_with, :atom, constraints: [one_of: [:USDC]]
      argument :slippage_percent, :string, constraints: @text
      argument :signer, :string, constraints: [trim?: false]

      run fn %{arguments: args}, %{actor: actor} ->
        prepare_step(
          fn -> Regents.Autolaunch.prepare_bid(drop_nils(args), actor: actor) end,
          AgentBid.Refused
        )
      end
    end

    action :bid_settlement_prepare, :map do
      argument :bid, :string, allow_nil?: false, constraints: [trim?: false]
      argument :signer, :string, constraints: [trim?: false]

      run fn %{arguments: args}, %{actor: actor} ->
        prepare_step(
          fn -> Regents.Autolaunch.prepare_bid_settlement(drop_nils(args), actor: actor) end,
          AgentBid.Refused
        )
      end
    end

    action :robinhood_bid_prepare, :map do
      argument :auction_id, :uuid, allow_nil?: false
      argument :usdg_amount, :string, allow_nil?: false, constraints: @text
      argument :max_price, :string, allow_nil?: false, constraints: @text
      argument :slippage_percent, :string, constraints: @text
      argument :signer, :string, constraints: [trim?: false]

      run fn %{arguments: args}, %{actor: actor} ->
        prepare_step(
          fn -> Regents.Autolaunch.prepare_robinhood_bid(drop_nils(args), actor: actor) end,
          AgentRobinhoodBid.Refused
        )
      end
    end

    action :robinhood_bid_settlement_prepare, :map do
      argument :bid, :string, allow_nil?: false, constraints: [trim?: false]
      argument :signer, :string, constraints: [trim?: false]

      run fn %{arguments: args}, %{actor: actor} ->
        prepare_step(
          fn ->
            Regents.Autolaunch.prepare_robinhood_bid_settlement(drop_nils(args), actor: actor)
          end,
          AgentRobinhoodBid.Refused
        )
      end
    end

    action :launch_prepare, :map do
      argument :draft, :uuid, allow_nil?: false
      argument :signer, :string, constraints: [trim?: false]

      run fn %{arguments: args}, %{actor: actor} ->
        prepare_step(
          fn -> Regents.Autolaunch.prepare_launch(drop_nils(args), actor: actor) end,
          AgentLaunch.Refused
        )
      end
    end

    action :finish_prepare, :map do
      argument :auction_id, :uuid, allow_nil?: false
      argument :signer, :string, constraints: [trim?: false]

      run fn %{arguments: args}, %{actor: actor} ->
        prepare_step(
          fn -> Regents.Autolaunch.prepare_finish(drop_nils(args), actor: actor) end,
          AgentFinish.Refused
        )
      end
    end

    action :stake_prepare, :map do
      argument :token_id, :uuid, allow_nil?: false
      argument :kind, :atom, allow_nil?: false, constraints: [one_of: [:stake, :unstake, :claim]]
      argument :amount, :string, constraints: @text
      argument :signer, :string, constraints: [trim?: false]

      run fn %{arguments: args}, %{actor: actor} ->
        prepare_step(
          fn -> Regents.Autolaunch.prepare_stake(drop_nils(args), actor: actor) end,
          AgentStake.Refused
        )
      end
    end
  end

  @doc false
  def save(kind, arguments, actor) do
    if Regents.Autolaunch.Prelaunch.read_only?(),
      do: {:error, Prelaunch.refusal()},
      else:
        kind
        |> AccountAnswer.save_draft(AccountAnswer.draft_params(arguments), actor)
        |> ApiError.data()
  end

  defp prepare_step(fun, refused_mod) do
    if Regents.Autolaunch.Prelaunch.read_only?() do
      {:error, Prelaunch.refusal()}
    else
      case fun.() do
        {:ok, answer} ->
          {:ok, answer}

        {:error, %Ash.Error.Unknown{errors: [%{__struct__: ^refused_mod} = refused | _]}} ->
          {:error, refused}

        {:error, %Ash.Error.Invalid{}} ->
          {:error, refused_mod.exception(reason: :invalid_request)}

        {:error, %Ash.Error.Forbidden{}} ->
          {:error, refused_mod.exception(reason: :invalid_request)}

        {:error, other} ->
          {:error, other}
      end
    end
  end

  defp drop_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
