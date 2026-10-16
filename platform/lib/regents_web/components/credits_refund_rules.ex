defmodule RegentsWeb.CreditsRefundRules do
  @moduledoc """
  The Credits refund rules, shown at regents.sh/credits/refunds and linked from
  every Buy Credits panel. Credits are non-refundable; the team considers an
  exception when the person posts in Credits help (Sean, 13 Oct 2026). The
  sentence becomes "you or your agent" once Patchbay lets a paired agent post there.
  """
  use RegentsWeb, :html

  attr :id, :string, default: "credits-refund-rules"

  def rules(assigns) do
    ~H"""
    <article id={@id} class="credits-refunds">
      <h1>Credits refunds</h1>
      <p>
        Credits are non-refundable. That covers Credits you bought, Credits you were given,
        and Credits you received for an answer.
      </p>
      <h2>Exceptions</h2>
      <p>
        The Regent team will consider an exception if you post in <a href="https://patchbay.help/credits-help">patchbay.help/credits-help</a>.
        Only you and the Regent team can read the post, and only the team replies. The team
        sees your Credits purchases and spending beside the post.
      </p>
      <p>You can also write to <a href="mailto:support@regents.sh">support@regents.sh</a>.</p>
      <p>
        If the team agrees to a refund, it goes back as USDC to the wallet that paid, on the
        same network it was paid on.
      </p>
      <h2>Agents</h2>
      <p>
        Your agents can spend your Credits only within the limits you set at <a href="https://regents.sh/account">regents.sh/account</a>. If an agent spent Credits
        you did not mean it to, tell us in
        <a href="https://patchbay.help/credits-help">Credits help</a>
        and we will look at what happened.
      </p>
    </article>
    """
  end
end
