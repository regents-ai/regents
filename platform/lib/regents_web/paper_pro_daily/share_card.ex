defmodule RegentsWeb.PaperProDaily.ShareCard do
  @moduledoc "The pictures shown when Paper Pro Daily or one of its papers is shared."

  alias RegentsWeb.PaperProDaily.Reading
  alias RegentsWeb.PublicDocuments
  alias Vix.Vips.{Image, Operation}

  @width 1200
  @height 630
  @margin 72
  @text_width @width - 2 * @margin
  @ground 11
  @ink "#E5E3D2"
  @muted "#9A988C"
  @title_sizes [68, 56, 46, 38, 32]
  @title_height 340

  @doc """
  Points text drawing at the card's own font, the only one it needs. Fontconfig
  reads this once, on the first text drawn, so the application sets it at start.
  """
  def use_own_font do
    System.put_env("FONTCONFIG_FILE", Application.app_dir(:regents, "priv/share_card/fonts.conf"))
  end

  @doc "The feed's picture: its heading alone."
  def page do
    picture = title(PublicDocuments.paper_share_heading())

    ground()
    |> place(picture, div(@height - Image.height(picture), 2))
    |> png()
  end

  @doc "A paper's picture: the heading, its title and its authors."
  def paper(paper) do
    card =
      ground()
      |> place(line(PublicDocuments.paper_share_heading(), @muted), @margin)
      |> place(title(paper.title), 150)

    case Reading.byline(paper) do
      "" ->
        png(card)

      byline ->
        byline
        |> line(@ink)
        |> then(&place(card, &1, @height - @margin - Image.height(&1)))
        |> png()
    end
  end

  defp ground do
    Operation.black!(@width, @height, bands: 3)
    |> Operation.linear!([1.0], [@ground * 1.0])
    |> Operation.cast!(:VIPS_FORMAT_UCHAR)
    |> Operation.copy!(interpretation: :VIPS_INTERPRETATION_sRGB)
  end

  defp line(words, colour), do: text(words, colour, 30)

  # A long title takes the largest size that stays clear of the authors.
  defp title(words) do
    pictures = Enum.map(@title_sizes, &text(words, @ink, &1))
    Enum.find(pictures, List.last(pictures), &(Image.height(&1) <= @title_height))
  end

  defp text(words, colour, size) do
    markup = ~s(<span foreground="#{colour}">#{Plug.HTML.html_escape(words)}</span>)

    {picture, _dpi} =
      Operation.text!(markup,
        font: "Geist Serif #{size}",
        width: @text_width,
        rgba: true,
        dpi: 72
      )

    picture
  end

  defp place(card, picture, top) do
    Operation.composite2!(card, picture, :VIPS_BLEND_MODE_OVER, x: @margin, y: top)
    |> Operation.flatten!()
  end

  defp png(card) do
    {:ok, bytes} = Image.write_to_buffer(card, ".png")
    bytes
  end
end
