defmodule Regents.Blog.Changes.ValidateContent do
  @moduledoc false
  use Ash.Resource.Change

  @x_url ~r"\Ahttps://(?:x|twitter)\.com/[A-Za-z0-9_]{1,15}/?\z"
  @handle ~r/\A@?([A-Za-z0-9_]{1,15})\z/

  @impl true
  def change(changeset, _opts, _context) do
    authors = Ash.Changeset.get_attribute(changeset, :authors) || []
    authors = Enum.map(authors, &Map.update!(&1, :x, fn x -> x_url(x) end))

    changeset = Ash.Changeset.change_attribute(changeset, :authors, authors)

    changeset =
      if Enum.all?(authors, &Regex.match?(@x_url, &1.x)) do
        case authors do
          [first | _] -> Ash.Changeset.force_change_attribute(changeset, :author_x, first.x)
          [] -> changeset
        end
      else
        Ash.Changeset.add_error(changeset,
          field: :authors,
          message: "Each author needs an X handle or an HTTPS X profile link."
        )
      end

    changeset =
      if is_binary(Ash.Changeset.get_attribute(changeset, :markdown)) and
           String.trim(Ash.Changeset.get_attribute(changeset, :markdown)) == "" do
        Ash.Changeset.add_error(changeset, field: :markdown, message: "Enter the article text.")
      else
        changeset
      end

    cover(changeset)
  end

  defp x_url(x) do
    case Regex.run(@handle, String.trim(x)) do
      [_, handle] -> "https://x.com/#{handle}"
      _ -> String.trim(x)
    end
  end

  defp cover(changeset) do
    case Ash.Changeset.get_attribute(changeset, :cover) do
      cover when is_binary(cover) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :cover_type,
          Regents.Blog.PostFile.cover_type!(cover)
        )

      _ ->
        changeset
    end
  rescue
    ArgumentError ->
      Ash.Changeset.add_error(changeset,
        field: :cover,
        message: "Choose a PNG, JPEG or WebP image."
      )
  end
end
