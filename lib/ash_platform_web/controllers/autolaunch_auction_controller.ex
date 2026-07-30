defmodule AshPlatformWeb.AutolaunchAuctionController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Accounts.VerifiedSession
  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch

  @modes ~w(all biddable live failed_minimum graduated)
  @sorts ~w(newest oldest)
  @query_parameters ~w(mode sort limit)

  def index(conn, params) do
    autolaunch = conn.private[:autolaunch_auction_controller_autolaunch] || Autolaunch

    with {:ok, mode, sort, limit} <- list_options(params),
         {:ok, auctions} <-
           autolaunch.list_public_auctions(mode, sort, limit, actor: nil) do
      json(conn, %{data: Enum.map(auctions, &public_auction/1)})
    else
      {:error, :invalid_query} -> invalid_request(conn)
      {:error, _error} -> internal_error(conn)
    end
  end

  def show(conn, %{"id" => id} = params) do
    autolaunch = conn.private[:autolaunch_auction_controller_autolaunch] || Autolaunch

    with true <- Map.keys(params) == ["id"],
         {:ok, _id} <- Ash.Type.UUID.cast_input(id, []),
         {:ok, auction} when not is_nil(auction) <-
           autolaunch.get_public_auction(id, actor: nil) do
      json(conn, %{data: public_auction(auction)})
    else
      false -> invalid_request(conn)
      :error -> not_found(conn)
      {:ok, nil} -> not_found(conn)
      {:error, _error} -> internal_error(conn)
    end
  end

  def bid_quote(conn, %{"id" => id} = params) do
    autolaunch = autolaunch(conn)

    with true <- Map.keys(params) |> Enum.sort() == ~w(amount id max_price),
         {:ok, quote} <-
           autolaunch.quote_auction_bid(id, params["amount"], params["max_price"]) do
      json(conn, %{data: quote})
    else
      false -> invalid_request(conn)
      {:error, :auction_not_found} -> not_found(conn)
      {:error, _reason} -> invalid_request(conn)
    end
  end

  def prepare_bid(conn, %{"id" => id} = params) do
    with {:ok, actor, wallet} <- current_human(conn),
         true <- Map.keys(params) |> Enum.sort() == ~w(amount id max_price),
         {:ok, envelope} <-
           autolaunch(conn).prepare_auction_bid(
             id,
             wallet,
             params["amount"],
             params["max_price"],
             actor: actor
           ) do
      json(conn, %{data: envelope})
    else
      {:error, :authentication_required} -> unauthorized(conn)
      false -> invalid_request(conn)
      {:error, :auction_not_found} -> not_found(conn)
      {:error, _reason} -> invalid_request(conn)
    end
  end

  def prepare_bid_exit(conn, %{"id" => id} = params),
    do: prepare_position(conn, params, id, :prepare_bid_exit)

  def prepare_bid_return(conn, %{"id" => id} = params),
    do: prepare_position(conn, params, id, :prepare_bid_return)

  def prepare_bid_claim(conn, %{"id" => id} = params),
    do: prepare_position(conn, params, id, :prepare_bid_claim)

  defp list_options(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @query_parameters)),
         mode when mode in @modes <- Map.get(params, "mode", "all"),
         sort when sort in @sorts <- Map.get(params, "sort", "newest"),
         {:ok, limit} <- parse_limit(Map.get(params, "limit"), 50) do
      {:ok, mode, sort, limit}
    else
      _error -> {:error, :invalid_query}
    end
  end

  defp prepare_position(conn, params, id, function) do
    with {:ok, actor, _wallet} <- current_human(conn),
         true <- Map.keys(params) == ["id"],
         {:ok, envelope} <- apply(autolaunch(conn), function, [id, [actor: actor]]) do
      json(conn, %{data: envelope})
    else
      {:error, :authentication_required} -> unauthorized(conn)
      false -> invalid_request(conn)
      {:error, _reason} -> invalid_request(conn)
    end
  end

  defp current_human(conn) do
    with id when is_integer(id) <- get_session(conn, :human_account_id),
         actor = %Human{human_account_id: id},
         {:ok, account} <- AshPlatform.Accounts.get_human_account(id, actor: actor),
         true <- VerifiedSession.current?(account),
         wallet when is_binary(wallet) <- account.wallet_address do
      {:ok, actor, wallet}
    else
      _ -> {:error, :authentication_required}
    end
  end

  defp autolaunch(conn),
    do: conn.private[:autolaunch_auction_controller_autolaunch] || Autolaunch

  defp parse_limit(nil, maximum), do: {:ok, maximum}

  defp parse_limit(value, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} -> {:ok, limit |> max(1) |> min(maximum)}
      _error -> {:error, :invalid_query}
    end
  end

  defp parse_limit(_value, _maximum), do: {:error, :invalid_query}

  defp public_auction(auction) do
    %{
      id: auction.id,
      title: auction.title,
      summary: auction.summary,
      featured: auction.featured,
      state: to_string(auction.state),
      opened_at: iso8601(auction.opened_at)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(value), do: DateTime.to_iso8601(value)

  defp invalid_request(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{
        code: "invalid_request",
        message: "The query parameters are invalid."
      }
    })
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: %{
        code: "not_found",
        message: "Auction not found."
      }
    })
  end

  defp internal_error(conn) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{
      error: %{
        code: "internal_error",
        message: "The request could not be completed."
      }
    })
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
  end
end
