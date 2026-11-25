defmodule RegentsWeb.Autolaunch.AgentTools.Market do
  @moduledoc """
  Public Autolaunch market reads exposed through the unified `/mcp` server:
  auction list, auction detail, bid estimate, token list, token detail, and
  treasury security report.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: RegentsWeb.Autolaunch.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Autolaunch.{ApiError, MarketAnswer}

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
