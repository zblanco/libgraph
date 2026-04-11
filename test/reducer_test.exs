defmodule Multigraph.Reducer.Test do
  use ExUnit.Case, async: true
  doctest Multigraph.Reducers.Bfs
  doctest Multigraph.Reducers.Dfs

  test "can walk a graph depth-first" do
    g =
      Multigraph.new()
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g])
      |> Multigraph.add_edge(:a, :b)
      |> Multigraph.add_edge(:b, :c)
      |> Multigraph.add_edge(:b, :d)
      |> Multigraph.add_edge(:c, :e)
      |> Multigraph.add_edge(:d, :f)
      |> Multigraph.add_edge(:f, :g)

    expected = [:a, :b, :c, :e, :d, :f, :g]
    assert ^expected = Multigraph.Reducers.Dfs.map(g, fn v -> v end)
  end

  test "can walk a graph breadth-first" do
    g =
      Multigraph.new()
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g])
      |> Multigraph.add_edge(:a, :b)
      |> Multigraph.add_edge(:a, :d)
      |> Multigraph.add_edge(:b, :c)
      |> Multigraph.add_edge(:b, :d)
      |> Multigraph.add_edge(:c, :e)
      |> Multigraph.add_edge(:d, :f)
      |> Multigraph.add_edge(:f, :g)

    expected = [:a, :b, :d, :c, :f, :e, :g]
    assert ^expected = Multigraph.Reducers.Bfs.map(g, fn v -> v end)
  end

  test "can walk a graph breadth-first, when the starting points had their in-edges deleted" do
    g =
      Multigraph.new()
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g])
      |> Multigraph.add_edge(:a, :b)
      |> Multigraph.add_edge(:a, :d)
      |> Multigraph.add_edge(:b, :c)
      |> Multigraph.add_edge(:b, :d)
      |> Multigraph.add_edge(:c, :e)
      |> Multigraph.add_edge(:d, :f)
      |> Multigraph.add_edge(:f, :g)
      # Add this edge and then remove it
      |> Multigraph.add_edge(:b, :a)
      |> Multigraph.delete_edge(:b, :a)

    expected = [:a, :b, :d, :c, :f, :e, :g]
    assert ^expected = Multigraph.Reducers.Bfs.map(g, fn v -> v end)
  end
end
