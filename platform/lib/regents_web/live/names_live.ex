defmodule RegentsWeb.NamesLive do
  @moduledoc """
  The Regent names the signed-in wallets have claimed, oldest first, and the form
  that claims another with a free claim. Everything here is read from the
  sign-in the shell already holds; nothing on the page asks the visitor to sign
  in again.
  """

  use RegentsWeb, :html

  import RegentsWeb.Components.PageHead, only: [page_head: 1]

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :names, :any, default: nil
  attr :stream, :any, required: true
  attr :claims, :any, default: nil
  attr :claim_name, :map, required: true

  def page(assigns) do
    ~H"""
    <article id="names-page" class="account-page rg-utility">
      <.page_head title="Names">
        <:tip>Your .regent.eth names, and claiming a new one.</:tip>
      </.page_head>

      <Regent.Account.signed_out
        :if={is_nil(@account)}
        id="names-signed-out"
        reason={@signed_out_reason}
      >
        <:sign_in>
          <Regent.Primitives.button type="button" data-account-target="sign-in">
            Sign in
          </Regent.Primitives.button>
        </:sign_in>
      </Regent.Account.signed_out>

      <div :if={@account} class="account-grid">
        <section class="account-panel account-names" aria-labelledby="account-names-title">
          <div class="account-names__heading">
            <h2 id="account-names-title">Your names</h2>
          </div>
          <.names names={@names} stream={@stream} />
        </section>

        <section class="account-panel account-claim" aria-labelledby="account-claim-title">
          <div class="account-names__heading">
            <h2 id="account-claim-title">Claim</h2>
            <.claims_available claims={@claims} />
          </div>
          <form id="account-claim-form" phx-change="check_claim_name" phx-submit="claim_name">
            <Regent.Primitives.field
              :let={field}
              id="account-claim-name"
              label="Name"
              errors={@claim_name.problems}
            >
              <div class="account-claim__name">
                <input
                  id={field.id}
                  name="name"
                  value={@claim_name.value}
                  autocomplete="off"
                  autocapitalize="none"
                  spellcheck="false"
                  placeholder="yourname"
                  phx-debounce="300"
                  aria-invalid={field.aria_invalid}
                  aria-describedby={field.described_by}
                />
                <span>.regent.eth</span>
              </div>
              <:hint>
                3 to 14 characters: lowercase letters, numbers and hyphens, not starting or ending with a hyphen.
              </:hint>
            </Regent.Primitives.field>
            <Regent.Primitives.button
              id="account-claim-submit"
              type="submit"
              disabled={not claimable?(@claims, @claim_name)}
              phx-disable-with="Claiming…"
            >
              Claim name
            </Regent.Primitives.button>
          </form>
          <.claim_name_availability name={@claim_name} />
          <%!-- The price is the one every paid claim on record was bought at. --%>
          <p :if={match?(%{free: 0}, @claims)} class="account-claim__later">
            Names cost 0.0025 ETH each, and buying one from this page isn’t open yet.
          </p>
        </section>
      </div>
    </article>
    """
  end

  attr :names, :any, default: nil
  attr :stream, :any, required: true

  defp names(%{names: :unavailable} = assigns) do
    ~H"""
    <p role="status">Your claimed names couldn’t be read right now. Refresh to try again.</p>
    """
  end

  defp names(%{names: %{empty?: true}} = assigns) do
    ~H"""
    <p>No names are claimed by your wallets yet.</p>
    """
  end

  # Each claim is shown by its ENS name. The rows come down once and stay in
  # the browser; more are added as the reader reaches the end.
  defp names(assigns) do
    ~H"""
    <ul
      id="account-names"
      class="account-names__list"
      phx-update="stream"
      phx-hook="MotionList"
      data-layout-id="account-names"
      data-children="li"
      data-variant={RegentsWeb.Motion.standard("list")}
    >
      <li :for={{id, claim} <- @stream} id={id} data-layout-id={id}>
        <strong>{claim.ens_fqdn}</strong>
        <div>
          <span>{String.capitalize(claim.claim_status)}</span>
          <span>Claimed {date(claim.created_at)}</span>
        </div>
      </li>
    </ul>
    <p
      :if={@names.more?}
      id="account-names-more"
      class="account-names__more"
      role="status"
      phx-hook="InfiniteScroll"
      data-event="load_more_names"
      data-cursor={@names.cursor}
    >
      Loading more names…
    </p>
    <p :if={@names.stalled?} role="status">
      More names couldn’t be loaded right now. Refresh to try again.
    </p>
    """
  end

  # How many claims the wallets may still make. A count that could not be read
  # is never shown as none.
  attr :claims, :any, required: true

  defp claims_available(%{claims: :unavailable} = assigns) do
    ~H"""
    <p id="account-claims-available" role="status">
      Your free claims couldn’t be read right now. Refresh to try again.
    </p>
    """
  end

  # Only free claims can be spent here; paid claims are counted but not usable.
  defp claims_available(assigns) do
    ~H"""
    <p id="account-claims-available">
      <span :if={@claims.free > 0}>
        You can claim {count(@claims.free, "more name", "more names")} free.
      </span>
      <span :if={@claims.free == 0}>No free claims on your wallets.</span>
      <span :if={@claims.paid > 0}>
        You also have {count(@claims.paid, "paid claim", "paid claims")}, which this page can’t use yet.
      </span>
    </p>
    """
  end

  attr :name, :map, required: true

  defp claim_name_availability(%{name: %{availability: :available}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__available">
      {@name.value}.regent.eth is available.
    </p>
    """
  end

  defp claim_name_availability(%{name: %{availability: :claimed}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__claimed">
      {@name.value} is already claimed.
    </p>
    """
  end

  defp claim_name_availability(%{name: %{availability: {:claimed_now, _name}}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__available">
      {elem(@name.availability, 1)} is yours.
    </p>
    """
  end

  defp claim_name_availability(%{name: %{availability: :not_claimed}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__claimed">
      Couldn’t claim {@name.value}.regent.eth right now. Try again in a moment.
    </p>
    """
  end

  defp claim_name_availability(%{name: %{availability: :unavailable}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status">
      Couldn’t check whether {@name.value} is claimed right now. Try again in a moment.
    </p>
    """
  end

  defp claim_name_availability(assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" hidden></p>
    """
  end

  # The button waits for a name that passed every check and a free claim to
  # spend on it; the lines beside it say which of the two is missing.
  defp claimable?(%{free: free}, %{availability: :available}) when free > 0, do: true
  defp claimable?(_claims, _claim_name), do: false

  defp count(1, singular, _plural), do: "1 #{singular}"
  defp count(n, _singular, plural), do: "#{n} #{plural}"

  defp date(datetime), do: Calendar.strftime(datetime, "%-d %B %Y")
end
