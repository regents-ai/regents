defmodule RegentsWeb.CreditsHistory do
  @moduledoc """
  The signed-in account's Credits purchases, newest first: what was paid, on
  which chain, what came of it and a link to the transaction. The library lets
  a person read only their own purchases and refunds.

  The parent passes the signed-in `account`, read as `Regents.Credits.person/1`,
  and its `balance`, so a purchase that counts while the page is open shows at
  once.
  """
  use RegentsWeb, :live_component

  alias Regent.Primitives, as: P
  alias RegentCredits.{Amount, Purchase, Refund}
  alias Regents.Credits

  require Ash.Query

  @page 25

  @impl true
  def mount(socket),
    do:
      {:ok,
       socket
       |> RegentsWeb.Live.Session.check_component_events(&take_account/2)
       |> assign(shown: @page)}

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :lease, :balance]))
     |> take_account(assigns.account)
     |> read()}
  end

  # The account as the page gave it, or as it reads now before each event
  # (`RegentsWeb.Live.Session.check_component_events/2`).
  defp take_account(socket, account), do: assign(socket, actor: Credits.person(account))

  @impl true
  def handle_event("more", _params, socket),
    do: {:noreply, socket |> update(:shown, &(&1 + @page)) |> read()}

  # One more than is shown, to know whether there are more.
  defp read(%{assigns: %{actor: actor, shown: shown}} = socket) do
    query = Purchase |> Ash.Query.sort(inserted_at: :desc) |> Ash.Query.limit(shown + 1)
    {purchases, rest} = Enum.split(RegentCredits.purchases!(actor: actor, query: query), shown)
    ids = Enum.map(purchases, & &1.id)

    refunds =
      RegentCredits.refunds!(actor: actor, query: Ash.Query.filter(Refund, purchase_id in ^ids))
      |> Map.new(&{&1.purchase_id, &1})

    assign(socket, purchases: purchases, refunds: refunds, more?: rest != [])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="credits-history">
      <div :if={@purchases == []} class="credits-history__empty">
        <p>No purchases yet.</p>
        <P.button
          type="button"
          phx-click={Phoenix.LiveView.JS.dispatch("regents:open", to: "#shell-credits")}
        >
          Buy Credits
        </P.button>
      </div>

      <ul :if={@purchases != []} class="credits-history__list">
        <li
          :for={purchase <- @purchases}
          class="credits-history__row"
          data-outcome={outcome(purchase, @refunds[purchase.id])}
        >
          <div class="credits-history__what">
            <strong>{usdc(purchase.amount)}</strong>
            <span>{day(purchase)} · {chain_name(purchase.chain)}</span>
          </div>
          <div class="credits-history__outcome">
            <strong>{words(purchase, @refunds[purchase.id])}</strong>
            <a
              href={Regents.Credits.transaction_url(purchase.chain, purchase.tx_hash)}
              target="_blank"
              rel="noopener"
              aria-label={"View this transaction on #{explorer_name(purchase.chain)}"}
            >
              View
            </a>
          </div>
        </li>
      </ul>

      <P.button :if={@more?} variant="quiet" type="button" phx-click="more" phx-target={@myself}>
        Show more
      </P.button>
    </div>
    """
  end

  defp outcome(_purchase, %Refund{}), do: "refunded"
  defp outcome(purchase, nil), do: Atom.to_string(purchase.status)

  defp words(_purchase, %Refund{status: :locked}), do: "Refund started"
  defp words(_purchase, %Refund{status: :sent}), do: "Refunded"

  defp words(%{status: :credited, amount: amount}, nil),
    do: "+" <> Amount.format(amount)

  defp words(%{status: :checking}, nil), do: "Checking"
  defp words(%{status: :failed}, nil), do: "No Credits added"

  defp usdc(amount), do: "#{amount |> Decimal.normalize() |> Decimal.to_string(:normal)} USDC"

  defp day(purchase), do: Calendar.strftime(purchase.inserted_at, "%-d %b %Y")

  defp chain_name(:base), do: "Base"
  defp chain_name(:ethereum), do: "Ethereum"

  defp explorer_name(:base), do: "Basescan"
  defp explorer_name(:ethereum), do: "Etherscan"
end
