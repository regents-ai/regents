defmodule RegentsWeb.CreditsRefundRules do
  @moduledoc """
  The Credits refund rules, shown at regents.sh/credits/refunds and linked from
  every Buy Credits panel. The page and agents read the same Markdown, so the two
  never differ. Credits are non-refundable; the team considers an exception when
  the person posts in Credits help (Sean, 13 Oct 2026). The sentence becomes "you
  or your agent" once Patchbay lets a paired agent post there.
  """
  use RegentsWeb, :html

  @doc "The rules, as the page shows them and agents read them."
  def markdown do
    """
    # Credits refunds

    Credits are non-refundable. That covers Credits you bought, Credits you were given, and Credits you received for an answer.

    ## Exceptions

    The Regent team will consider an exception if you post in [patchbay.help/credits-help](https://patchbay.help/credits-help). Only you and the Regent team can read the post, and only the team replies. The team sees your Credits purchases and spending beside the post.

    You can also write to [support@regents.sh](mailto:support@regents.sh).

    If the team agrees to a refund, it goes back as USDC to the wallet that paid, on the same network it was paid on.

    ## Agents

    Your agents can spend your Credits only within the limits you set at [regents.sh/account](https://regents.sh/account). If an agent spent Credits you did not mean it to, tell us in [Credits help](https://patchbay.help/credits-help) and we will look at what happened.
    """
  end

  attr :id, :string, default: "credits-refund-rules"

  def rules(assigns) do
    ~H"""
    <article id={@id} class="credits-refunds">
      {RegentsWeb.PublicDocuments.html(markdown())}
    </article>
    """
  end
end
