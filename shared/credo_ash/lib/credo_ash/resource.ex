defmodule CredoAsh.Resource do
  @moduledoc """
  Shared AST helpers for recognising Ash resource modules and their
  authorization surface.
  """

  @authorizer [:Ash, :Policy, :Authorizer]

  @typedoc "What one `defmodule` told us about itself as an Ash resource."
  @type info :: %{
          line: pos_integer(),
          module: String.t(),
          data_layer: :embedded | :other | :none,
          authorizer?: boolean(),
          policies_line: pos_integer() | nil
        }

  @doc """
  Returns one entry per Ash resource module in the source file.

  Each `defmodule` is inspected on its own: a nested module never contributes
  its `policies do` block to its parent, and modules that merely
  `use Ash.Resource.Change` (and friends) are not resources at all.
  """
  @spec infos(Macro.t()) :: [info()]
  def infos(ast) do
    ast
    |> modules()
    |> Enum.flat_map(&info/1)
  end

  defp modules(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [{:__aliases__, _, parts}, [{:do, body} | _]]} = node, acc ->
          {node, [{Enum.map_join(parts, ".", &Atom.to_string/1), body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(modules)
  end

  defp info({module, body}) do
    statements = own_statements(body)

    case Enum.find_value(statements, &resource_use/1) do
      nil ->
        []

      {line, opts} ->
        [
          %{
            line: line,
            module: module,
            data_layer: data_layer(opts),
            authorizer?: authorizer?(opts),
            policies_line: policies_line(statements)
          }
        ]
    end
  end

  # Statements written directly in this module's body, with nested modules
  # collapsed away so their contents are attributed to them and not to us.
  defp own_statements({:__block__, _, statements}), do: statements
  defp own_statements(nil), do: []
  defp own_statements(statement), do: [statement]

  defp resource_use({:use, meta, [{:__aliases__, _, [:Ash, :Resource]} | rest]}) do
    {meta[:line], use_opts(rest)}
  end

  defp resource_use(_), do: nil

  defp use_opts([opts]) when is_list(opts), do: opts
  defp use_opts(_), do: []

  defp data_layer(opts) do
    case Keyword.fetch(opts, :data_layer) do
      {:ok, :embedded} -> :embedded
      {:ok, _} -> :other
      :error -> :none
    end
  end

  defp authorizer?(opts) do
    opts
    |> Keyword.get(:authorizers, [])
    |> List.wrap()
    |> Enum.any?(&match?({:__aliases__, _, @authorizer}, &1))
  end

  defp policies_line(statements) do
    Enum.find_value(statements, fn
      {:policies, meta, [[{:do, _} | _]]} -> meta[:line]
      _ -> nil
    end)
  end
end
