defmodule RegentsWeb.Autolaunch.AgentTools.Account do
  @moduledoc """
  Paired-agent private Autolaunch reads and launch draft saves exposed through
  the unified `/mcp` server: Revstake and Memestock drafts and wallet positions.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: RegentsWeb.Autolaunch.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Autolaunch.{AccountAnswer, ApiError, Prelaunch}

  # Text goes to the draft as the route takes it: untrimmed, empty included.
  @text [allow_empty?: true, trim?: false]

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

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
