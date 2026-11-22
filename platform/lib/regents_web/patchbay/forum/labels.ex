defmodule RegentsWeb.Patchbay.Forum.Labels do
  @moduledoc """
  The marks a report or a reply can carry, in the one wording every page
  uses. A report is marked "Bounty paid" once the money held for it has gone
  to the accepted answer's author, and "Replay verified" when Patchbay matched
  it to its own record of the call. A post is marked "Caution" when the
  reading before it was published found code or commands in it that could
  harm whoever runs them; nothing marks code as safe. Each mark stands on its
  own, so a report can be both paid out and verified.
  """

  use Phoenix.Component

  @caution "Caution"
  @caution_note "Code in this post may be unsafe to run."

  @doc "The caution mark's word."
  @spec caution() :: String.t()
  def caution, do: @caution

  @doc "The sentence a cautioned post carries, on its page and in its Markdown."
  @spec caution_note() :: String.t()
  def caution_note, do: @caution_note

  @doc "The marks one report carries, in their fixed order."
  @spec report(map(), atom()) :: [String.t()]
  def report(report, _edition \\ :main) do
    for {true, mark} <- [
          {report.escrow_status == :released, "Bounty paid"},
          {report.verified, "Replay verified"},
          {report.code_caution, @caution}
        ],
        do: mark
  end

  @doc "The marks one reply carries."
  @spec reply(map(), atom()) :: [String.t()]
  def reply(reply, _edition \\ :main) do
    if reply.code_caution, do: [@caution], else: []
  end

  attr :report, :any, required: true

  @doc "A report's marks as pills, beside its verdict in a list of reports."
  def report_badges(assigns) do
    ~H"""
    <span
      :for={mark <- report(@report)}
      class={["patchbay-pill", if(mark == caution(), do: "is-caution", else: "is-good")]}
    >
      {mark}
    </span>
    """
  end

  @doc "The caution mark, beside a post's other marks on its page."
  def caution_mark(assigns) do
    ~H"""
    <span class="pb-kind-pill is-caution">{caution()}</span>
    """
  end

  attr :id, :string, required: true

  @doc "The sentence a cautioned post carries above its words."
  def caution_line(assigns) do
    ~H"""
    <p id={@id} class="pb-caution-line">
      <Regent.Icons.icon name="triangle-alert" class="pb-caution-icon" />
      <span>{caution_note()}</span>
    </p>
    """
  end
end
