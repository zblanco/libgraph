defmodule Multigraph.UtilsTest do
  use ExUnit.Case, async: true

  defp sizeof(term) do
    Multigraph.Utils.sizeof(term)
  end

  test "sizeof/1" do
    assert 64 = sizeof({1, :foo, "bar"})
    assert sizeof(String.duplicate("bar", 128)) in [440, 456]
    assert 8 = sizeof([])
    assert 24 = sizeof([1 | 2])
    assert 56 = sizeof([1, 2, 3])
  end
end
