defmodule RegentsWeb.Patchbay.Forum.Labels do
  @moduledoc """
  The caution a report or a reply carries, in the one wording every page
  uses. A post is marked "Caution" when the reading before it was published
  found code or commands in it that could harm whoever runs them; nothing
  marks code as safe.
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
