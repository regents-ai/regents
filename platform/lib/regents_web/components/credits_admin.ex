defmodule RegentsWeb.CreditsAdmin do
  @moduledoc """
  The Credits admin page's parts, shown at regents.sh/admin/credits: give
  Credits, find a person's purchases and start a refund, then close each
  refund with the Treasury Safe's USDC transfer.

  The host passes `account`, the signed-in account, and its `session_lease` as
  `lease`; the panel acts as `Regents.Credits.admin/1` of it, and the library
  refuses everything here to anyone not named in its `:admins` setting.
  """
  use RegentsWeb, :live_component

  require Ash.Query

  alias Regent.Primitives, as: P
  alias RegentCredits.{Amount, Chains, Purchase, Refund}
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}
  alias Regents.Credits

  @hash ~r/0x[0-9a-fA-F]{64}/
  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> RegentsWeb.Live.Session.check_component_events(&take_account/2)
     |> assign(
       gift_key: Ecto.UUID.generate(),
       gift_note: nil,
       search: "",
       purchases: nil,
       refunded: %{},
       refund_note: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :lease]))
     |> take_account(assigns.account)
     |> read_refunds()}
  end

  # The account as the page gave it, or as it reads now before each event
  # (`RegentsWeb.Live.Session.check_component_events/2`).
  defp take_account(socket, account), do: assign(socket, actor: Credits.admin(account))

  @impl true
  def handle_event("give", %{"to" => to, "amount" => amount, "note" => note}, socket) do
    recipients = to |> String.split([",", "\n", " "], trim: true) |> Enum.map(&String.trim/1)

    result =
      with {:ok, amount} <- Decimal.parse(String.trim(amount)) |> parsed(),
           do:
             RegentCredits.give(socket.assigns.gift_key, recipients, amount, %{note: blank(note)},
               actor: socket.assigns.actor
             )

    case result do
      {:ok, gifts} ->
        {:noreply,
         assign(socket,
           gift_key: Ecto.UUID.generate(),
           gift_note:
             {:ok, "Gave #{Amount.format(hd(gifts).amount)} to #{recipients(length(gifts))}."}
         )}

      {:error, error} ->
        {:noreply, assign(socket, gift_note: {:error, gift_words(error)})}
    end
  end

  def handle_event("find", %{"search" => search}, socket) do
    {:noreply, socket |> assign(search: String.trim(search)) |> find()}
  end

  def handle_event("start_refund", %{"id" => id}, socket) do
    note =
      case RegentCredits.start_refund(id, actor: socket.assigns.actor) do
        {:ok, _refund} -> {:ok, "Refund started. Its Credits are locked; send the USDC below."}
        {:error, error} -> {:error, refund_words(error)}
      end

    {:noreply, socket |> assign(refund_note: note) |> find() |> read_refunds()}
  end

  def handle_event("close_refund", %{"refund" => id, "link" => link}, socket) do
    note =
      with [hash] <- Regex.run(@hash, link),
           {:ok, _refund} <- RegentCredits.close_refund(id, hash, actor: socket.assigns.actor) do
        {:ok, "Refund closed."}
      else
        nil -> {:error, "Paste the transaction link or hash from the Treasury Safe's transfer."}
        {:error, error} -> {:error, refund_words(error)}
      end

    {:noreply, socket |> assign(refund_note: note) |> find() |> read_refunds()}
  end

  defp parsed({amount, ""}), do: {:ok, amount}
  defp parsed(_other), do: {:error, Refused.exception(reason: :invalid_amount)}

  defp blank(""), do: nil
  defp blank(text), do: String.trim(text)

  defp find(%{assigns: %{search: ""}} = socket), do: assign(socket, purchases: nil, refunded: %{})

  # The person's purchases, newest first, and the refund of each one refunded.
  defp find(%{assigns: %{search: search, actor: actor}} = socket) do
    who = String.downcase(search)

    purchases =
      RegentCredits.purchases!(
        actor: actor,
        query:
          Purchase
          |> Ash.Query.filter(wallet == ^who or privy_user_id == ^search)
          |> Ash.Query.sort(inserted_at: :desc)
      )

    ids = Enum.map(purchases, & &1.id)

    refunded =
      RegentCredits.refunds!(actor: actor, query: Ash.Query.filter(Refund, purchase_id in ^ids))
      |> Map.new(&{&1.purchase_id, &1})

    assign(socket, purchases: purchases, refunded: refunded)
  end

  defp read_refunds(socket) do
    refunds =
      RegentCredits.refunds!(
        actor: socket.assigns.actor,
        query: Refund |> Ash.Query.filter(status == :locked) |> Ash.Query.sort(inserted_at: :asc)
      )

    assign(socket, refunds: refunds)
  end

  defp gift_words(%Ash.Error.Invalid{errors: [error | _]}), do: gift_words(error)

  defp gift_words(%Refused{reason: :invalid_recipient}),
    do: "Each recipient must be a wallet address or a Privy account id."

  defp gift_words(%Refused{reason: :invalid_amount}),
    do: "Enter an amount above zero, to at most six decimal places."

  defp gift_words(%Refused{reason: :key_reused}),
    do: "These Credits were already given. Reload the page to give again."

  defp gift_words(%Ash.Error.Forbidden{}), do: "Only a Credits admin can give Credits."
  defp gift_words(_other), do: "Nothing was given. Try again."

  defp refund_words(%Ash.Error.Invalid{errors: [error | _]}), do: refund_words(error)

  defp refund_words(%Refused{reason: :used}),
    do: "This account has used Credits, so its purchases can't be refunded."

  defp refund_words(%Refused{reason: :not_credited}),
    do: "This purchase never added Credits, so there is nothing to refund."

  defp refund_words(%Refused{reason: :refund_not_proven}),
    do:
      "That transaction isn't a successful transfer of exactly this refund from the Treasury Safe to the wallet that paid."

  defp refund_words(%NotEnoughCredits{}),
    do: "The account no longer holds these purchased Credits."

  defp refund_words(%Ash.Error.Forbidden{}), do: "Only a Credits admin can refund."
  defp refund_words(_other), do: "Nothing changed. Try again."

  defp state(_purchase, %{status: :locked}), do: "refund started"
  defp state(_purchase, %{status: :sent}), do: "refunded"
  defp state(%{status: :checking}, nil), do: "being checked"
  defp state(%{status: :credited}, nil), do: "credited"
  defp state(%{status: :failed, reason: reason}, nil), do: "not credited (#{reason})"

  # Credits waiting under a wallet no account holds have no account to take
  # them back from.
  defp refundable?(%{status: :credited, privy_user_id: owner}, nil), do: owner != nil
  defp refundable?(_purchase, _refund), do: false

  defp usdc(amount), do: "#{plain(amount)} USDC"

  defp plain(amount), do: amount |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp sent_on(purchase), do: Calendar.strftime(purchase.inserted_at, "%d %b %Y %H:%M UTC")

  defp chain_name(:base), do: "Base"
  defp chain_name(:ethereum), do: "Ethereum"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, treasury: Chains.treasury())

    ~H"""
    <div id={@id} class="credits-admin">
      <section class="credits-admin__part" aria-labelledby={"#{@id}-give"}>
        <h2 id={"#{@id}-give"}>Give Credits</h2>
        <p>
          Given Credits never expire and are never refunded. A gift to a wallet with no account waits until that wallet signs in.
        </p>
        <form id={"#{@id}-give-form"} phx-submit="give" phx-target={@myself}>
          <P.field :let={field} id={"#{@id}-to"} label="Wallet addresses or Privy account ids">
            <textarea id={field.id} name="to" rows="4" required></textarea>
            <:hint>One per line, or separated by commas.</:hint>
          </P.field>
          <P.field :let={field} id={"#{@id}-amount"} label="Credits each">
            <input id={field.id} name="amount" inputmode="decimal" autocomplete="off" required />
          </P.field>
          <P.field :let={field} id={"#{@id}-note"} label="Note (optional)">
            <input id={field.id} name="note" autocomplete="off" />
          </P.field>
          <P.button type="submit" phx-disable-with="Giving…">Give</P.button>
        </form>
        <P.notice :if={@gift_note} tone={if elem(@gift_note, 0) == :ok, do: "success", else: "error"}>
          {elem(@gift_note, 1)}
        </P.notice>
      </section>

      <section class="credits-admin__part" aria-labelledby={"#{@id}-find"}>
        <h2 id={"#{@id}-find"}>Purchases</h2>
        <form id={"#{@id}-find-form"} phx-submit="find" phx-target={@myself}>
          <P.field :let={field} id={"#{@id}-search"} label="Wallet address or Privy account id">
            <input id={field.id} name="search" value={@search} autocomplete="off" />
          </P.field>
          <P.button type="submit" variant="secondary">Find</P.button>
        </form>
        <p :if={@purchases == []}>No purchases from {@search}.</p>
        <ul :if={@purchases not in [nil, []]} class="credits-admin__list">
          <li :for={purchase <- @purchases}>
            <p>
              <strong>{usdc(purchase.amount)} on {chain_name(purchase.chain)}</strong>
              · {state(purchase, @refunded[purchase.id])} · {sent_on(purchase)}
            </p>
            <p :if={purchase.privy_user_id}>Account <code>{purchase.privy_user_id}</code></p>
            <p :if={is_nil(purchase.privy_user_id)}>Waiting for the wallet's owner to sign in</p>
            <p>From <code>{purchase.wallet}</code></p>
            <p>
              <a href={Regents.Credits.transaction_url(purchase.chain, purchase.tx_hash)}>Transaction</a>
            </p>
            <P.button
              :if={refundable?(purchase, @refunded[purchase.id])}
              type="button"
              variant="secondary"
              phx-click="start_refund"
              phx-value-id={purchase.id}
              phx-target={@myself}
              data-confirm={"Lock #{plain(purchase.amount)} purchased Credits for a refund?"}
            >
              Refund
            </P.button>
          </li>
        </ul>
      </section>

      <section class="credits-admin__part" aria-labelledby={"#{@id}-refunds"}>
        <h2 id={"#{@id}-refunds"}>Refunds to send</h2>
        <P.notice
          :if={@refund_note}
          tone={if elem(@refund_note, 0) == :ok, do: "success", else: "error"}
        >
          {elem(@refund_note, 1)}
        </P.notice>
        <p :if={@refunds == []}>None waiting.</p>
        <ul :if={@refunds != []} class="credits-admin__list">
          <li :for={refund <- @refunds}>
            <p>
              Send exactly <strong>{usdc(refund.amount)}</strong>
              on <strong>{chain_name(refund.chain)}</strong>
              from the Treasury Safe <code>{@treasury}</code>
              to <code>{refund.wallet}</code>.
            </p>
            <form id={"#{@id}-close-#{refund.id}"} phx-submit="close_refund" phx-target={@myself}>
              <input type="hidden" name="refund" value={refund.id} />
              <P.field :let={field} id={"#{@id}-link-#{refund.id}"} label="Transaction link">
                <input id={field.id} name="link" autocomplete="off" required />
              </P.field>
              <P.button type="submit" phx-disable-with="Checking…">Close refund</P.button>
            </form>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp recipients(1), do: "1 recipient"
  defp recipients(count), do: "#{count} recipients"
end
