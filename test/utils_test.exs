defmodule Graph.UtilsTest do
  use ExUnit.Case, async: true

  defp sizeof(term) do
    Graph.Utils.sizeof(term)
  end

  test "sizeof/1" do
    assert 64 = sizeof({1, :foo, "bar"})

    # String internal representation changed in OTP 27, accepting both old (440) and new (456) sizes
    string_size = sizeof(String.duplicate("bar", 128))
    assert string_size == 440 or string_size == 456
    assert 8 = sizeof([])
    assert 24 = sizeof([1 | 2])
    assert 56 = sizeof([1, 2, 3])
  end
end
