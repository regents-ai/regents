defmodule AshPlatform.ContentCoordinatorTest do
  use ExUnit.Case, async: true

  alias AshPlatform.ContentCoordinator

  defmodule Provider do
    def load(_route_spec, %{value: value}), do: {:ok, value}
  end

  test "tags content results with the destination generation" do
    assert ContentCoordinator.load(7, :route, %{value: :content}, Provider) ==
             {7, {:ok, :content}}
  end
end
