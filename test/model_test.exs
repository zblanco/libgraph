defmodule Multigraph.ModelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag timeout: :infinity

  test "a directed acyclic graph (DAG) is always acyclic" do
    check all(g <- dag(), max_runs: 1000) do
      Multigraph.is_acyclic?(g)
    end
  end

  test "a directed acyclic graph (DAG) is always topologically sortable" do
    check all(g <- dag(), max_runs: 1000) do
      assert Multigraph.topsort(g) != false
    end
  end

  test "a topsort of a DAG is correct if each element only has edges pointing to subsequent elements" do
    check all(%Multigraph{vertices: vs, out_edges: oe} = g <- dag(), max_runs: 1000) do
      sorted = Multigraph.topsort(g)

      correct? =
        case sorted do
          false ->
            false

          _ ->
            {_, correct?} =
              Enum.reduce(sorted, {[], true}, fn
                _, {_, false} = res ->
                  res

                v, {visited, _} ->
                  v_id = Multigraph.Utils.vertex_id(v)
                  edges = Map.get(oe, v_id, MapSet.new())

                  backreferences? =
                    Enum.any?(edges, fn e -> Enum.member?(visited, Map.get(vs, e)) end)

                  {[v | visited], not backreferences?}
              end)

            correct?
        end

      assert correct?
    end
  end

  test "a directed cyclic graph (DCG) is always cyclic" do
    check all(g <- dcg(), max_runs: 1000) do
      assert Multigraph.is_cyclic?(g)
    end
  end

  test "a directed cyclic graph (DCG) is never topologically sortable" do
    check all(g <- dcg(), max_runs: 1000) do
      assert Multigraph.topsort(g) == false
    end
  end

  test "the out degree of a vertex is equal to the number of out neighbors of that vertex (DAG)" do
    check all(g <- dag()) do
      vs = Multigraph.vertices(g)

      assert Enum.reduce(vs, true, fn
               _, false ->
                 false

               v, _ ->
                 Multigraph.out_degree(g, v) == length(Multigraph.out_neighbors(g, v))
             end)
    end
  end

  test "the in degree of a vertex is equal to the number of in neighbors of that vertex (DAG)" do
    check all(g <- dag()) do
      vs = Multigraph.vertices(g)

      assert Enum.reduce(vs, true, fn
               _, false ->
                 false

               v, _ ->
                 Multigraph.in_degree(g, v) == length(Multigraph.in_neighbors(g, v))
             end)
    end
  end

  test "the out degree of a vertex is equal to the number of out neighbors of that vertex (DCG)" do
    check all(g <- dcg()) do
      vs = Multigraph.vertices(g)

      assert Enum.reduce(vs, true, fn
               _, false ->
                 false

               v, _ ->
                 Multigraph.out_degree(g, v) == length(Multigraph.out_neighbors(g, v))
             end)
    end
  end

  test "the in degree of a vertex is equal to the number of in neighbors of that vertex (DCG)" do
    check all(g <- dcg()) do
      vs = Multigraph.vertices(g)

      assert Enum.reduce(vs, true, fn
               _, false ->
                 false

               v, _ ->
                 Multigraph.in_degree(g, v) == length(Multigraph.in_neighbors(g, v))
             end)
    end
  end

  test "the subgraph G' of a given graph G, implies that the vertices and edges of G' form subsets of those from G (DAG)" do
    check all(g <- dag(), Multigraph.num_vertices(g) > 0) do
      g_vertices = g |> Multigraph.vertices() |> MapSet.new()
      g_edges = g |> Multigraph.edges() |> MapSet.new()

      subset_vertices =
        g_vertices |> Enum.shuffle() |> Enum.take(:rand.uniform(MapSet.size(g_vertices) - 1))

      sg = Multigraph.subgraph(g, subset_vertices)
      sg_vertices = sg |> Multigraph.vertices() |> MapSet.new()
      sg_edges = sg |> Multigraph.edges() |> MapSet.new()
      assert MapSet.subset?(sg_vertices, g_vertices) && MapSet.subset?(sg_edges, g_edges)
    end
  end

  test "the subgraph G' of a given graph G, implies that the vertices and edges of G' form subsets of those from G (DCG)" do
    check all(g <- dcg()) do
      g_vertices = g |> Multigraph.vertices() |> MapSet.new()
      g_edges = g |> Multigraph.edges() |> MapSet.new()

      subset_vertices =
        g_vertices |> Enum.shuffle() |> Enum.take(:rand.uniform(MapSet.size(g_vertices) - 1))

      sg = Multigraph.subgraph(g, subset_vertices)
      sg_vertices = sg |> Multigraph.vertices() |> MapSet.new()
      sg_edges = sg |> Multigraph.edges() |> MapSet.new()
      assert MapSet.subset?(sg_vertices, g_vertices) && MapSet.subset?(sg_edges, g_edges)
    end
  end

  test "connected components of a graph are lists of vertices where exists an adirectional path between each pair of vertices" do
    check all(g <- dag(), Multigraph.num_vertices(g) > 0) do
      components = Multigraph.components(g)

      assert Enum.all?(components, fn
               component when length(component) < 2 ->
                 true

               component ->
                 for j <- component, k <- component, j != k do
                   Multigraph.get_shortest_path(g, j, k) != nil ||
                     Multigraph.get_shortest_path(g, k, j) != nil
                 end
             end)
    end
  end

  test "strongly connected components of a graph are lists of vertices where exits a bidirectional path between each pair of vertices" do
    check all(g <- dcg()) do
      strong_components = Multigraph.strong_components(g)

      assert Enum.all?(strong_components, fn
               component ->
                 for j <- component, k <- component, j != k do
                   Multigraph.get_shortest_path(g, j, k) != nil &&
                     Multigraph.get_shortest_path(g, j, k) != nil
                 end
             end)
    end
  end

  test "the degeneracy core of a DAG is the maximum k_core of a given graph" do
    check all(g <- dag()) do
      k_cores = Multigraph.k_core_components(g)
      degeneracy = Multigraph.degeneracy(g)
      degeneracy_core = g |> Multigraph.degeneracy_core() |> Multigraph.vertices()
      {k, core} = Enum.max_by(k_cores, fn {k, _} -> k end)
      assert degeneracy == k and MapSet.equal?(MapSet.new(core), MapSet.new(degeneracy_core))
    end
  end

  test "the degeneracy core of a DCG is the maximum k_core of a given graph" do
    check all(g <- dcg()) do
      k_cores = Multigraph.k_core_components(g)
      degeneracy = Multigraph.degeneracy(g)
      degeneracy_core = g |> Multigraph.degeneracy_core() |> Multigraph.vertices()
      {k, core} = Enum.max_by(k_cores, fn {k, _} -> k end)
      assert degeneracy == k and MapSet.equal?(MapSet.new(core), MapSet.new(degeneracy_core))
    end
  end

  ## Private

  def dag() do
    filter(sized_dag(), &Multigraph.is_acyclic?/1)
  end

  defp sized_dag() do
    sized(fn size -> sized_dag(size, Multigraph.new()) end)
  end

  defp sized_dag(0, g) do
    constant(g)
  end

  defp sized_dag(i, g) do
    i = i + 1
    g = Enum.reduce(0..i, g, fn v, g -> Multigraph.add_vertex(g, v) end)

    graph =
      Enum.reduce(1..i, g, fn v, g ->
        if v + 1 > i do
          g
        else
          r = (v + 1)..i
          v2s = Stream.iterate(Enum.random(r), fn _ -> Enum.random(r) end)

          Enum.reduce(Enum.take(v2s, :rand.uniform(6)), g, fn v2, acc ->
            Multigraph.add_edge(acc, v, v2)
          end)
        end
      end)

    constant(graph)
  end

  def dcg() do
    filter(sized_dcg(), &Multigraph.is_cyclic?/1)
  end

  defp sized_dcg() do
    sized(fn size -> sized_dcg(size, Multigraph.new()) end)
  end

  # We cannot produce a "real" DCG unless we have at least 2 vertices,
  # as a single vertex DCG which has an edge to itself is still topsortable
  # and so does not hold to the property that DCGs are not topsortable
  # We are handling it this way to maintain compatibility with digraph (for now),
  # but this may change in the future
  defp sized_dcg(size, g) when size < 2 do
    sized_dcg(size + 1, g)
  end

  defp sized_dcg(0, g), do: constant(g)

  defp sized_dcg(1, g), do: constant(g)

  defp sized_dcg(i, g) do
    g = Enum.reduce(0..i, g, fn v, g -> Multigraph.add_vertex(g, v) end)

    graph =
      Enum.reduce(0..i, g, fn v, g ->
        r = 0..i

        Stream.iterate(Enum.random(r), fn _ -> Enum.random(r) end)
        |> Stream.filter(fn v2 -> v2 != v end)
        |> Enum.take(:rand.uniform(6))
        |> Enum.reduce(g, fn v2, acc -> Multigraph.add_edge(acc, v, v2) end)
      end)

    constant(graph)
  end

  def mesh() do
    gen all(graph <- sized_mesh(), Multigraph.is_cyclic?(graph) and strongly_connected?(graph)) do
      graph
    end
  end

  defp sized_mesh() do
    sized(fn size -> sized_mesh(size, Multigraph.new()) end)
  end

  defp sized_mesh(size, g) when size < 2 do
    sized_mesh(size + 1, g)
  end

  defp sized_mesh(size, g) do
    g = Enum.reduce(0..size, g, fn v, g -> Multigraph.add_vertex(g, v) end)
    vs = Multigraph.vertices(g)

    graph =
      Enum.reduce(vs, g, fn v, acc ->
        Enum.reduce(vs, acc, fn
          ^v, acc2 ->
            acc2

          v2, acc2 ->
            Multigraph.add_edge(acc2, v, v2)
        end)
      end)

    constant(graph)
  end

  defp strongly_connected?(graph) do
    num_vertices = Multigraph.num_vertices(graph)

    Enum.reduce(graph.vertices, true, fn
      _, false ->
        false

      {v_id, _v}, _acc ->
        out_edges = Map.get(graph.out_edges, v_id, MapSet.new()) |> MapSet.delete(v_id)
        in_edges = Map.get(graph.in_edges, v_id, MapSet.new()) |> MapSet.delete(v_id)

        MapSet.size(out_edges) == num_vertices - 1 &&
          MapSet.size(in_edges) == num_vertices - 1 &&
          MapSet.size(MapSet.difference(out_edges, in_edges)) == 0
    end)
  end
end
