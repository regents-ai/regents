defmodule Regents.Patchbay.Changelog do
  @moduledoc """
  patchbay.help's changelog (`priv/patchbay/CHANGELOG.md`, its repository's root
  changelog), embedded in the release with newest entries first.
  """

  @path Application.app_dir(:regents, "priv/patchbay/CHANGELOG.md")
  @external_resource @path
  @document @path
            |> File.read!()
            |> MDEx.parse_document!(extension: [inline_code_attributes: false])
  @intro Enum.take_while(@document.nodes, &(!match?(%MDEx.Heading{level: 2}, &1)))
  # An entry marked `<!-- open -->` is shown at patchbay.help's other address too;
  # the marker itself is never shown.
  @dated @document.nodes
         |> Enum.drop(length(@intro))
         |> Enum.chunk_while(
           [],
           fn
             %MDEx.Heading{level: 2} = node, [] -> {:cont, [node]}
             %MDEx.Heading{level: 2} = node, acc -> {:cont, Enum.reverse(acc), [node]}
             node, acc -> {:cont, [node | acc]}
           end,
           fn
             [] -> {:cont, []}
             acc -> {:cont, Enum.reverse(acc), []}
           end
         )
         |> Enum.map(fn [heading | body] ->
           title = MDEx.to_markdown!(%{@document | nodes: [heading]}) |> String.trim()

           [date] =
             Regex.run(~r/\A## (\d{4}-\d{2}-\d{2}) — .+\z/u, title, capture: :all_but_first)

           body =
             Enum.reject(body, fn
               %MDEx.HtmlBlock{literal: text} -> String.trim(text) == "<!-- open -->"
               _other -> false
             end)

           {Date.from_iso8601!(date), [heading | body]}
         end)
         |> Enum.sort_by(&elem(&1, 0), {:desc, Date})

  @per_page 12
  @entries @dated
           |> Enum.with_index()
           |> Enum.map(fn {{_date, nodes}, index} ->
             %{
               id: length(@dated) - index,
               nodes: nodes,
               html: Regents.Patchbay.AddressText.html(%{@document | nodes: nodes})
             }
           end)
  @pages @entries |> Enum.map(&Map.take(&1, [:id, :html])) |> Enum.chunk_every(@per_page)
  @intro_html Regents.Patchbay.AddressText.html(%{
                @document
                | nodes: Enum.reject(@intro, &match?(%MDEx.Heading{level: 1}, &1))
              })
  @markdown MDEx.to_markdown!(%{@document | nodes: @intro ++ Enum.flat_map(@entries, & &1.nodes)})

  @doc "One page of the dated entries, newest first, and the number of pages."
  @spec page(pos_integer()) :: {:ok, [map()], pos_integer()} | :error
  def page(number) when number > 0 do
    case Enum.fetch(@pages, number - 1) do
      {:ok, entries} -> {:ok, entries, length(@pages)}
      :error -> :error
    end
  end

  @doc "The words before the first entry, as the entries' pieces (`Regents.Patchbay.AddressText.html/1`)."
  def intro, do: @intro_html

  @doc "The whole changelog as Markdown, newest entries first."
  def markdown, do: @markdown
end
