defmodule RegentsWeb.Patchbay.Forum.Board do
  @moduledoc """
  Every read the board pages make beside their question lists, in one place.
  So far the home page's search matches. Nothing here writes.
  """

  alias Regents.Patchbay.Forum

  # A site card's tool count is what Patchbay's own check found
  # (`Regents.Patchbay.Forum.SiteCheck.tools/1`), so every card is read with
  # its check.
  @card_loads [:site_check, :report_count]

  @doc """
  The sites and tools whose names match what a visitor typed into the front
  page's search, for the answers shown above the matching discussions. Fewer
  than two letters matches nothing.
  """
  @spec matches(String.t()) ::
          {:ok, %{sites: [Forum.Site.t()], tools: [Forum.Tool.t()]}} | {:error, term()}
  def matches(q) do
    text = String.trim(q)

    if String.length(text) >= 2 do
      with {:ok, sites} <- Forum.find_sites(text, load: @card_loads),
           {:ok, tools} <- Forum.find_tools(text),
           do: {:ok, %{sites: sites, tools: tools}}
    else
      {:ok, %{sites: [], tools: []}}
    end
  end
end
