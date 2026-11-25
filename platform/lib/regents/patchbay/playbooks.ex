defmodule Regents.Patchbay.Playbooks do
  @moduledoc """
  Composable agent support playbooks (analogous to `agentic.market` Bundles),
  parsed at compile time from `priv/patchbay/playbooks/*.md`. Each playbook
  carries a copyable multi-step Agent Prompt and checklist across x402, MPP
  (Tempo), Agentic Commerce, and `cve.now` Cybersecurity workflows.
  """

  @directory "priv/patchbay/playbooks"
  @paths @directory
         |> File.ls!()
         |> Enum.filter(&String.ends_with?(&1, ".md"))
         |> Enum.sort()
  for path <- @paths, do: @external_resource(Path.join(@directory, path))
  @external_resource @directory

  @playbooks Enum.map(@paths, fn filename ->
               slug = Path.rootname(filename)
               text = File.read!(Path.join(@directory, filename))
               ["", header, body] = String.split(text, ~r/^---$/m, parts: 3)

               fields =
                 header
                 |> String.split("\n", trim: true)
                 |> Map.new(fn line ->
                   [k, v] = String.split(line, ":", parts: 2)
                   {String.trim(k), String.trim(v)}
                 end)

               sections =
                 ~r/^## (.+)$/m
                 |> Regex.split(body, include_captures: true, trim: true)
                 |> Enum.drop_while(&(String.trim(&1) == ""))
                 |> Enum.chunk_every(2)
                 |> Map.new(fn ["## " <> name, content] ->
                   {String.trim(name), String.trim(content)}
                 end)

               prompt =
                 sections
                 |> Map.get("Agent Prompt", "")
                 |> String.replace(~r/\A```[a-z]*\n/i, "")
                 |> String.replace(~r/\n```\z/, "")
                 |> String.trim()

               checks =
                 sections
                 |> Map.get("Included Checks", "")
                 |> String.split("\n", trim: true)
                 |> Enum.map(&String.replace_prefix(&1, "- ", ""))

               %{
                 slug: slug,
                 title: Map.fetch!(fields, "title"),
                 pillar: Map.fetch!(fields, "pillar"),
                 estimated_cost: Map.fetch!(fields, "estimated_cost"),
                 protocols:
                   fields
                   |> Map.get("protocols", "")
                   |> String.split(",", trim: true)
                   |> Enum.map(&String.trim/1),
                 services:
                   fields
                   |> Map.get("services", "")
                   |> String.split(",", trim: true)
                   |> Enum.map(&String.trim/1),
                 summary: Map.fetch!(fields, "summary"),
                 objective: Map.get(sections, "Objective", ""),
                 prompt: prompt,
                 checks: checks,
                 raw_markdown: text
               }
             end)

  @doc "All launch playbooks in canonical order."
  @spec all() :: [map()]
  def all, do: @playbooks

  @doc "Find a single playbook by slug."
  @spec get(String.t()) :: map() | nil
  def get(slug) when is_binary(slug), do: Enum.find(@playbooks, &(&1.slug == slug))
  def get(_other), do: nil

  @doc "Search playbooks by query text."
  @spec search(String.t()) :: [map()]
  def search(query) when is_binary(query) do
    needle = query |> String.trim() |> String.downcase()

    if needle == "" do
      @playbooks
    else
      Enum.filter(@playbooks, fn pb ->
        haystack =
          [
            pb.title,
            pb.pillar,
            pb.summary,
            Enum.join(pb.protocols, " "),
            Enum.join(pb.services, " ")
          ]
          |> Enum.join(" ")
          |> String.downcase()

        String.contains?(haystack, needle)
      end)
    end
  end

  def search(_other), do: @playbooks
end
