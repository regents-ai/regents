defmodule RegentsWeb.Autolaunch.AgentTools.Market do
  @moduledoc """
  Public Autolaunch market reads exposed through the unified `/mcp` server:
  auction list, auction counts, auction detail, bid estimate, token list,
  token detail, treasury security report, and Isolated Exposure series reads.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: RegentsWeb.Autolaunch.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Autolaunch.Exposure
  alias RegentsWeb.Autolaunch.{ApiError, ExposureAnswer, MarketAnswer, Refusal}

  actions do
    action :auctions_answer, :map do
      argument :after, :string, constraints: [allow_empty?: true, trim?: false]
      argument :q, :string, constraints: [allow_empty?: true, trim?: false]
      argument :chain, :atom, constraints: [one_of: [:all, :base, :robinhood]]
      argument :kind, :atom, constraints: [one_of: [:all, :revstake, :memestock]]
      argument :x, :boolean
      argument :ens, :boolean
      argument :github, :boolean

      argument :state, :atom,
        constraints: [one_of: [:all, :created, :active, :ended, :failed, :graduated, :finished]]

      argument :sort, :atom, constraints: [one_of: [:newest, :ending, :volume]]
      argument :limit, :integer

      run fn input, _context ->
        input.arguments
        |> MarketAnswer.params()
        |> MarketAnswer.auctions()
      end
    end

    action :auction_answer, :map do
      argument :id, :string, allow_nil?: false, constraints: [trim?: false]

      run fn input, _context ->
        input.arguments
        |> MarketAnswer.params()
        |> MarketAnswer.auction()
      end
    end

    action :counts_answer, :map do
      run fn _input, _context ->
        case Regents.Autolaunch.auction_counts(actor: nil) do
          {:ok, counts} ->
            {:ok, counts}

          {:error, _error} ->
            {:error,
             Refusal.new(
               :internal_server_error,
               "internal_error",
               "The request could not be completed."
             )}
        end
      end
    end

    action :bid_quote_answer, :map do
      argument :id, :string, allow_nil?: false, constraints: [trim?: false]

      argument :amount, :string,
        allow_nil?: false,
        constraints: [allow_empty?: true, trim?: false]

      argument :max_price, :string,
        allow_nil?: false,
        constraints: [allow_empty?: true, trim?: false]

      run fn input, _context ->
        input.arguments
        |> MarketAnswer.params()
        |> MarketAnswer.bid_quote()
        |> ApiError.data()
      end
    end

    action :tokens_answer, :map do
      argument :after, :string, constraints: [allow_empty?: true, trim?: false]
      argument :q, :string, constraints: [allow_empty?: true, trim?: false]
      argument :chain, :atom, constraints: [one_of: [:all, :base, :robinhood]]
      argument :kind, :atom, constraints: [one_of: [:all, :revstake, :memestock]]
      argument :x, :boolean
      argument :ens, :boolean
      argument :github, :boolean
      argument :limit, :integer

      run fn input, _context ->
        input.arguments
        |> MarketAnswer.params()
        |> MarketAnswer.tokens()
      end
    end

    action :token_answer, :map do
      argument :id, :string, allow_nil?: false, constraints: [trim?: false]

      run fn input, _context ->
        input.arguments
        |> MarketAnswer.params()
        |> MarketAnswer.token()
        |> ApiError.data()
      end
    end

    action :treasury_answer, :map do
      argument :address, :string, allow_nil?: false, constraints: [trim?: false]

      run fn input, _context ->
        input.arguments
        |> MarketAnswer.params()
        |> MarketAnswer.treasury()
        |> ApiError.data()
      end
    end

    action :after_hour_stocks_list, :map do
      run fn _input, _context ->
        Exposure.exposure_series_list(actor: nil)
        |> ExposureAnswer.answer(:list)
        |> case do
          {:ok, %{data: list}} -> {:ok, %{data: list}}
          {:error, refusal} -> {:error, refusal}
        end
      end
    end

    action :after_hour_stocks_series, :map do
      argument :series, :string, allow_nil?: false, constraints: [trim?: false]

      run fn %{arguments: %{series: series}}, _context ->
        Exposure.exposure_series(series, actor: nil)
        |> ExposureAnswer.answer(:series)
        |> ApiError.data()
      end
    end
  end

  policies do
    # Anyone reads public market tools, except a connected app calling as itself
    # (paired, it calls as its agent instead).
    policy always() do
      forbid_if actor_attribute_equals(:role, :connected_app)
      authorize_if always()
    end
  end
end
