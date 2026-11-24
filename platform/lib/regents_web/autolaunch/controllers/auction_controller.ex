defmodule RegentsWeb.Autolaunch.AuctionController do
  use RegentsWeb, :controller

  alias RegentAgentAccess.RateLimit
  alias Regents.Autolaunch.ReadFailure
  alias RegentsWeb.Autolaunch.{ApiError, MarketAnswer}
  alias RegentsWeb.ClientAddress

  plug :limit_list when action == :index

  # Each answer is the one its hosted MCP tool gives too (`RegentsWeb.Autolaunch.MarketAnswer`).
  def index(conn, params), do: ApiError.answer(conn, MarketAnswer.auctions(params))

  # Any listed auction is named by its id; a Robinhood auction also by its
  # contract address.
  def show(conn, params), do: ApiError.answer(conn, MarketAnswer.auction(params))

  @doc """
  Live and graduated auction counts for each launch type and chain, from the
  action the hosted MCP tool runs too (`Regents.Autolaunch.Auction`, `:counts`).
  """
  def counts(conn, params) do
    with true <- params == %{},
         {:ok, counts} <- Regents.Autolaunch.auction_counts(actor: nil) do
      json(conn, %{data: counts})
    else
      false -> ApiError.answer(conn, MarketAnswer.invalid_query())
      {:error, error} -> internal_error(conn, "public auction counts read", error)
    end
  end

  def bid_quote(conn, params), do: ApiError.answer(conn, MarketAnswer.bid_quote(params))

  defp limit_list(conn, _opts) do
    RateLimit.call(
      conn,
      MarketAnswer.list_limit(fn request ->
        {key, _source} = ClientAddress.key(request)
        key
      end)
    )
  end

  # A read that failed is logged by its kind and module only, then answered
  # with the generic error (`Regents.Autolaunch.ReadFailure`).
  defp internal_error(conn, what, error) do
    ReadFailure.log(what, error)

    ApiError.send(
      conn,
      :internal_server_error,
      "internal_error",
      "The request could not be completed."
    )
  end
end
