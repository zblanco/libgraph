defmodule MultigraphTest do
  use ExUnit.Case, async: true
  doctest Multigraph
  doctest Multigraph.Edge
  alias Multigraph.Edge
  alias Multigraph.Test.Generators

  test "injectable vertex_identifier" do
    g = Multigraph.new()

    g_with_custom_vertex_identifier =
      Multigraph.new(vertex_identifier: fn v -> :erlang.phash2(v, trunc(:math.pow(2, 16))) end)

    g = Multigraph.add_vertex(g, :v1, :labelA)

    g_with_custom_vertex_identifier =
      Multigraph.add_vertex(g_with_custom_vertex_identifier, :v1, :labelA)

    assert Multigraph.has_vertex?(g, :v1)
    assert Multigraph.has_vertex?(g_with_custom_vertex_identifier, :v1)
  end

  describe "multigraphs" do
    test "`multigraph: true` option enables edge indexing on edge labels" do
      graph =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b},
          {:a, :b, label: :foo},
          {:a, :b, label: :bar},
          {:b, :c, weight: 3},
          {:b, :a, label: {:complex, :label}}
        ])

      assert Enum.count(Multigraph.out_edges(graph, :a)) == 3
      assert [%Edge{label: :foo}] = Multigraph.out_edges(graph, :a, by: [:foo])
      assert [%Edge{label: :foo}] = Multigraph.out_edges(graph, :a, by: :foo)
      assert [%Edge{label: :foo}] = Multigraph.in_edges(graph, :b, by: :foo)
      assert [%Edge{label: :bar}] = Multigraph.out_edges(graph, :a, by: :bar)
      assert [%Edge{label: nil}] = Multigraph.out_edges(graph, :a, by: nil)

      assert [%Edge{label: nil}] = Multigraph.out_edges(graph, :a, by: nil)

      assert [%Edge{label: {:complex, :label}}] =
               Multigraph.out_edges(graph, :b,
                 where: fn edge -> edge.label == {:complex, :label} or edge.label == :bar end
               )

      assert 1 == graph |> Multigraph.edges(by: :foo) |> Enum.count()
      assert 1 == graph |> Multigraph.edges(where: fn edge -> edge.weight > 2 end) |> Enum.count()

      assert 1 ==
               graph
               |> Multigraph.edges(:a, by: :foo)
               |> Enum.count()

      assert 2 ==
               graph
               |> Multigraph.edges(by: [:foo, :bar])
               |> Enum.count()

      assert 1 ==
               graph
               |> Multigraph.edges(by: [:foo, :bar], where: fn edge -> edge.label == :bar end)
               |> Enum.count()

      assert [] == Multigraph.out_edges(graph, :a, by: :foobar)
    end

    test "custom edge partition_by function" do
      graph =
        Multigraph.new(multigraph: true, partition_by: fn edge -> [edge.weight] end)
        |> Multigraph.add_edges([
          {:a, :b},
          {:a, :b, label: :foo},
          {:a, :b, label: :bar},
          {:b, :c, weight: 3},
          {:b, :a, weight: 6}
        ])

      assert Enum.count(Multigraph.out_edges(graph, :b)) == 2

      assert [%Edge{weight: 6}] =
               Multigraph.out_edges(graph, :b, where: fn edge -> edge.weight == 6 end)

      assert [%Edge{weight: 3}] =
               Multigraph.out_edges(graph, :b, where: fn edge -> edge.weight == 3 end)
    end

    test "custom partition_by supports indexing to more than one partition" do
      graph =
        Multigraph.new(multigraph: true, partition_by: fn edge -> [edge.weight, edge.label] end)
        |> Multigraph.add_edges([
          {:a, :b},
          {:a, :d, label: :foo},
          {:a, :b, label: :bar},
          {:b, :c, weight: 3},
          {:b, :a, weight: 6, label: :foo}
        ])

      assert Enum.count(Multigraph.out_edges(graph, :b)) == 2

      assert [%Edge{weight: 6, label: :foo}] =
               Multigraph.out_edges(graph, :b, by: 6)

      assert Enum.count(Multigraph.edges(graph, by: [:foo])) == 2
    end

    test "removing edges prunes index" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b},
          {:a, :b, label: :foo},
          {:a, :b, label: :bar},
          {:b, :c, weight: 3},
          {:b, :a, label: {:complex, :label}}
        ])

      g = Multigraph.delete_edges(g, [{:b, :c}, {:b, :a}])
      refute Map.has_key?(g.edge_index, {:complex, :label})
      assert Enum.empty?(Multigraph.edges(g, by: [{:complex, :label}]))
      # nil partition still exists for a->b nil-label edge
      assert Map.has_key?(g.edge_index, nil)
    end

    test "delete_edge/3 removes only a multigraph's properties and index for the given partition key/label" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b},
          {:a, :b, label: :foo},
          {:a, :b, label: :bar},
          {:b, :c, weight: 3},
          {:b, :a, label: {:complex, :label}}
        ])

      g = Multigraph.delete_edge(g, :a, :b, :foo)

      refute Map.has_key?(g.edge_index, :foo)
      assert Enum.empty?(Multigraph.out_edges(g, :a, by: :foo))
      assert Enum.empty?(Multigraph.edges(g, by: :foo))
    end

    test "update_labelled_edge/3 updates an indexed adge with new label" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b},
          {:a, :b, label: :foo},
          {:a, :b, label: :bar},
          {:b, :c, weight: 3},
          {:b, :a, label: {:complex, :label}}
        ])

      g = Multigraph.update_labelled_edge(g, :a, :b, :foo, label: :baz)

      refute Map.has_key?(g.edge_index, :foo)
      assert Map.has_key?(g.edge_index[:baz], g.vertex_identifier.(:a))
    end

    test "update_labelled_edge preserves sibling edges in partition index" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edge(:fact, :join, label: :runnable)
        |> Multigraph.add_edge(:fact, :step_a, label: :runnable)
        |> Multigraph.add_edge(:fact, :step_b, label: :runnable)

      assert length(Multigraph.edges(g, by: [:runnable])) == 3

      g = Multigraph.update_labelled_edge(g, :fact, :join, :runnable, label: :ran)

      ran_edges = Multigraph.edges(g, by: [:ran])
      assert length(ran_edges) == 1
      assert hd(ran_edges).v1 == :fact and hd(ran_edges).v2 == :join

      runnable_edges = Multigraph.edges(g, by: [:runnable])
      assert length(runnable_edges) == 2

      runnable_targets = Enum.map(runnable_edges, & &1.v2) |> Enum.sort()
      assert runnable_targets == [:step_a, :step_b]
    end

    test "delete_vertex prunes edge_index" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :foo},
          {:a, :c, label: :bar},
          {:b, :c, label: :foo},
          {:c, :d, label: :baz}
        ])

      assert Map.has_key?(g.edge_index, :foo)
      assert Map.has_key?(g.edge_index, :bar)

      g = Multigraph.delete_vertex(g, :a)

      refute Multigraph.has_vertex?(g, :a)
      # :bar partition only had a->c, should be gone
      refute Map.has_key?(g.edge_index, :bar)
      # :foo partition still has b->c
      assert Map.has_key?(g.edge_index, :foo)
      assert [%Edge{v1: :b, v2: :c, label: :foo}] = Multigraph.edges(g, by: [:foo])

      # no stale references to deleted vertex
      Enum.each(g.edge_index, fn {_partition, vertex_map} ->
        refute Map.has_key?(vertex_map, g.vertex_identifier.(:a))

        Enum.each(vertex_map, fn {_v_id, edge_keys} ->
          Enum.each(edge_keys, fn {v1_id, v2_id} ->
            refute v1_id == g.vertex_identifier.(:a)
            refute v2_id == g.vertex_identifier.(:a)
          end)
        end)
      end)
    end

    test "delete_vertices prunes edge_index" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :foo},
          {:b, :c, label: :bar},
          {:c, :d, label: :baz}
        ])

      g = Multigraph.delete_vertices(g, [:a, :c])

      refute Map.has_key?(g.edge_index, :foo)
      refute Map.has_key?(g.edge_index, :bar)
      refute Map.has_key?(g.edge_index, :baz)
      assert g.edge_index == %{}
    end

    test "transpose preserves edge_index with flipped edge keys" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :foo},
          {:b, :c, label: :bar}
        ])

      gt = Multigraph.transpose(g)

      assert [%Edge{v1: :b, v2: :a, label: :foo}] = Multigraph.out_edges(gt, :b, by: :foo)
      assert [%Edge{v1: :c, v2: :b, label: :bar}] = Multigraph.out_edges(gt, :c, by: :bar)
      assert Enum.empty?(Multigraph.out_edges(gt, :a, by: :foo))
    end

    test "split_edge prunes old edge and indexes new edges" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edge(:a, :c, label: :foo)
        |> Multigraph.add_edge(:a, :c, label: :bar)

      g = Multigraph.split_edge(g, :a, :c, :b)

      # old a->c edges should be gone from index
      a_id = g.vertex_identifier.(:a)
      c_id = g.vertex_identifier.(:c)

      Enum.each(g.edge_index, fn {_partition, vertex_map} ->
        Enum.each(vertex_map, fn {_v_id, edge_keys} ->
          refute MapSet.member?(edge_keys, {a_id, c_id})
        end)
      end)

      # new edges a->b and b->c should be indexed
      assert [%Edge{v1: :a, v2: :b, label: :foo}] = Multigraph.out_edges(g, :a, by: :foo)
      assert [%Edge{v1: :a, v2: :b, label: :bar}] = Multigraph.out_edges(g, :a, by: :bar)
      assert [%Edge{v1: :b, v2: :c, label: :foo}] = Multigraph.out_edges(g, :b, by: :foo)
      assert [%Edge{v1: :b, v2: :c, label: :bar}] = Multigraph.out_edges(g, :b, by: :bar)
    end

    test "subgraph preserves multigraph settings and rebuilds index" do
      g =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :foo},
          {:b, :c, label: :bar},
          {:c, :d, label: :baz}
        ])

      sg = Multigraph.subgraph(g, [:a, :b, :c])

      assert sg.multigraph == true
      assert [%Edge{v1: :a, v2: :b, label: :foo}] = Multigraph.edges(sg, by: [:foo])
      assert [%Edge{v1: :b, v2: :c, label: :bar}] = Multigraph.edges(sg, by: [:bar])
      # :baz edge is not in subgraph since :d is excluded
      assert Enum.empty?(Multigraph.edges(sg, by: [:baz]))
    end

    test "BFS traversal using multigraph partitions" do
      graph =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :foo},
          {:a, :b, label: :bar},
          {:a, :c, label: :foo},
          {:b, :d, label: :bar},
          {:c, :d, label: :foo}
        ])

      # BFS following only :foo edges: a -> b, a -> c, c -> d
      foo_result = Multigraph.Reducers.Bfs.map(graph, fn v -> v end, by: :foo)
      assert :a == hd(foo_result)
      assert MapSet.new(foo_result) == MapSet.new([:a, :b, :c, :d])

      # BFS following only :bar edges: a -> b, b -> d
      bar_result = Multigraph.Reducers.Bfs.map(graph, fn v -> v end, by: :bar)
      assert :a == hd(bar_result)
      assert MapSet.new(bar_result) == MapSet.new([:a, :b, :d])
    end

    test "DFS traversal using multigraph partitions" do
      graph =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :foo},
          {:a, :b, label: :bar},
          {:a, :c, label: :foo},
          {:b, :d, label: :bar},
          {:c, :d, label: :foo}
        ])

      # DFS following only :foo edges: a -> b, a -> c -> d
      foo_result = Multigraph.Reducers.Dfs.map(graph, fn v -> v end, by: :foo)
      assert :a == hd(foo_result)
      assert MapSet.new(foo_result) == MapSet.new([:a, :b, :c, :d])

      # DFS following only :bar edges: a -> b -> d
      bar_result = Multigraph.Reducers.Dfs.map(graph, fn v -> v end, by: :bar)
      assert :a == hd(bar_result)
      assert MapSet.new(bar_result) == MapSet.new([:a, :b, :d])
    end

    test "Dijkstra with multigraph partition filtering" do
      graph =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :fast, weight: 1},
          {:a, :c, label: :slow, weight: 10},
          {:b, :d, label: :fast, weight: 1},
          {:c, :d, label: :slow, weight: 1}
        ])

      # Via :fast edges only: a->b->d, cost 2
      assert [:a, :b, :d] = Multigraph.dijkstra(graph, :a, :d, by: :fast)

      # Via :slow edges only: a->c->d, cost 11
      assert [:a, :c, :d] = Multigraph.dijkstra(graph, :a, :d, by: :slow)

      # No :fast path from :a to :c
      assert nil == Multigraph.dijkstra(graph, :a, :c, by: :fast)
    end

    test "A* with multigraph partition filtering" do
      graph =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :fast, weight: 1},
          {:a, :c, label: :slow, weight: 10},
          {:b, :d, label: :fast, weight: 1},
          {:c, :d, label: :slow, weight: 1}
        ])

      assert [:a, :b, :d] = Multigraph.a_star(graph, :a, :d, fn _ -> 0 end, by: :fast)
      assert [:a, :c, :d] = Multigraph.a_star(graph, :a, :d, fn _ -> 0 end, by: :slow)
    end

    test "Bellman-Ford with multigraph partition filtering" do
      graph =
        Multigraph.new(multigraph: true)
        |> Multigraph.add_edges([
          {:a, :b, label: :fast, weight: 1},
          {:a, :c, label: :slow, weight: 10},
          {:b, :d, label: :fast, weight: 2},
          {:c, :d, label: :slow, weight: 1}
        ])

      result = Multigraph.bellman_ford(graph, :a, by: :fast)
      assert result[:a] == 0
      assert result[:b] == 1
      assert result[:d] == 3
      # :c is not reachable via :fast edges
      assert result[:c] == :infinity
    end
  end

  describe "edge properties" do
    test "setting edge properties" do
      g =
        Multigraph.new()
        |> Multigraph.add_edges([
          {:a, :b, properties: %{foo: :bar}},
          {:a, :b, label: :foo, properties: %{bar: :foo}}
        ])

      edges = Multigraph.out_edges(g, :a) |> Enum.sort_by(fn e -> {e.label != nil, e.label} end)

      assert [
               %Edge{v1: :a, v2: :b, properties: %{foo: :bar}},
               %Edge{v1: :a, v2: :b, label: :foo, properties: %{bar: :foo}}
             ] = edges
    end

    test "updating edge properties" do
      g =
        Multigraph.new()
        |> Multigraph.add_edges([
          {:a, :b, properties: %{foo: :bar}},
          {:a, :b, label: :foo, properties: %{bar: :foo}}
        ])
        |> Multigraph.update_edge(:a, :b, properties: %{ham: :potato})
        |> Multigraph.update_labelled_edge(:a, :b, :foo, properties: %{potato: :ham})

      edges = Multigraph.out_edges(g, :a) |> Enum.sort_by(fn e -> {e.label != nil, e.label} end)

      assert [
               %Edge{v1: :a, v2: :b, properties: %{ham: :potato}},
               %Edge{v1: :a, v2: :b, label: :foo, properties: %{potato: :ham}}
             ] = edges
    end

    test "adding edge struct with properties" do
      g =
        Multigraph.new()

      edge = Edge.new(:a, :b, properties: %{foo: :bar})

      g = Multigraph.add_edge(g, edge)

      assert [
               %Edge{v1: :a, v2: :b, properties: %{foo: :bar}}
             ] = Multigraph.out_edges(g, :a)
    end
  end

  test "delete vertex" do
    g = Multigraph.new()
    g = Multigraph.add_vertex(g, :v1, :labelA)
    g = Multigraph.delete_vertex(g, :v1)
    g = Multigraph.add_vertex(g, :v1, :labelB)

    assert [:labelB] = Multigraph.vertex_labels(g, :v1)
  end

  test "delete vertices" do
    graph =
      Multigraph.new()
      |> Multigraph.add_vertices([1, 2, 4, 6])
      |> Multigraph.add_edge(1, 2)
      |> Multigraph.add_edge(2, 4)
      |> Multigraph.add_edge(4, 6)

    graph_two =
      graph
      |> Multigraph.add_vertices([3, 5, 7])
      |> Multigraph.add_edge(1, 3)
      |> Multigraph.add_edge(3, 4)
      |> Multigraph.add_edge(3, 5)
      |> Multigraph.add_edge(5, 6)
      |> Multigraph.add_edge(5, 7)

    assert graph == Multigraph.delete_vertices(graph_two, [3, 5, 7])
  end

  test "inspect" do
    g =
      Multigraph.new()
      |> Multigraph.add_edges([
        {:a, :b},
        {:a, :b, label: :foo},
        {:b, :c, weight: 3},
        {:b, :a, label: {:complex, :label}}
      ])

    ug =
      Multigraph.new(type: :undirected)
      |> Multigraph.add_edges([
        {:a, :b},
        {:a, :b, label: :foo},
        {:b, :c, weight: 3},
        {:b, :a, label: {:complex, :label}}
      ])

    # structs: false
    structs_false = "#{inspect(g, structs: false)}"
    doc = Inspect.Algebra.format(Inspect.Algebra.to_doc(g, %Inspect.Opts{structs: false}), 99999)
    assert ^structs_false = :erlang.iolist_to_binary(doc)

    # pretty printed - edge order within a vertex pair is non-deterministic (map iteration)
    str = "#{inspect(g)}"

    assert str =~ ~r/^#Multigraph<type: directed, vertices: \[:a, :b, :c\], edges: \[/
    assert str =~ ":a -> :b"
    assert str =~ ":a -[foo]-> :b"
    assert str =~ ":b -[{:complex, :label}]-> :a"
    assert str =~ ":b -> :c"

    ustr = "#{inspect(ug)}"

    assert ustr =~ ~r/^#Multigraph<type: undirected, vertices: \[:a, :b, :c\], edges: \[/
    assert ustr =~ ":a <-> :b"
    assert ustr =~ ":a <-[foo]-> :b"
    assert ustr =~ ":a <-[{:complex, :label}]-> :b"
    assert ustr =~ ":b <-> :c"

    # large graph
    g = Enum.reduce(1..150, Multigraph.new(), fn i, g -> Multigraph.add_edge(g, i, i + 1) end)
    str = "#{inspect(g)}"
    assert "#Multigraph<type: directed, num_vertices: 151, num_edges: 150>" = str
  end

  test "get info about graph" do
    g = build_basic_cyclic_graph()
    assert %{type: :directed, num_vertices: 5, num_edges: 7} = Multigraph.info(g)
  end

  test "is_cyclic?" do
    dg = build_basic_cyclic_digraph()
    refute :digraph_utils.is_acyclic(dg)

    g = build_basic_cyclic_graph()
    assert Multigraph.is_cyclic?(g)
    refute Multigraph.is_acyclic?(g)
  end

  test "is_acyclic?" do
    dg = build_basic_acyclic_digraph()
    assert :digraph_utils.is_acyclic(dg)

    g = build_basic_acyclic_graph()
    assert Multigraph.is_acyclic?(g)
    refute Multigraph.is_cyclic?(g)
  end

  test "is_tree?" do
    dg = build_basic_tree_digraph()
    assert :digraph_utils.is_tree(dg)

    g = build_basic_tree_graph()
    assert Multigraph.is_tree?(g)
  end

  test "is_arborescence?" do
    dg = build_basic_tree_digraph()
    assert :digraph_utils.is_arborescence(dg)

    g = build_basic_tree_graph()
    assert Multigraph.is_arborescence?(g)
  end

  test "arborescence_root" do
    dg = build_basic_tree_digraph()
    assert {:yes, root} = :digraph_utils.arborescence_root(dg)

    g = build_basic_tree_graph()
    assert ^root = Multigraph.arborescence_root(g)
  end

  test "edges/2 returns both directions" do
    generated_result =
      Multigraph.new()
      |> Multigraph.add_edges([
        {:a, :b, label: "label1"},
        {:a, :b, label: "label2"},
        {:b, :a, label: "label3"}
      ])
      |> Multigraph.edges(:a)

    for edge <- generated_result do
      assert edge.label in ["label1", "label2", "label3"] and
               ((edge.v1 == :a and edge.v2 == :b) or
                  (edge.v1 == :b and edge.v2 == :a))
    end
  end

  test "is_subgraph?" do
    g = build_basic_tree_graph()
    sg = Multigraph.subgraph(g, [:a, :b, :c])
    assert Multigraph.is_subgraph?(sg, g)
  end

  test "topsort" do
    dg = build_basic_acyclic_digraph()
    dg_sorted = :digraph_utils.topsort(dg)
    assert is_list(dg_sorted)

    g = build_basic_acyclic_graph()
    assert ^dg_sorted = Multigraph.topsort(g)
  end

  test "find all paths" do
    g = build_basic_cyclic_graph()

    assert [[:a, :c, :d, :e], [:a, :b, :d, :e], [:a, :b, :c, :d, :e]] =
             Multigraph.get_paths(g, :a, :e)
  end

  test "find all paths on loopy graph" do
    g =
      Multigraph.new()
      |> Multigraph.add_edge(:a, :b)
      |> Multigraph.add_edge(:a, :c)
      |> Multigraph.add_edge(:b, :d)
      |> Multigraph.add_edge(:c, :d)
      |> Multigraph.add_edge(:d, :e)
      |> Multigraph.add_edge(:e, :d)
      |> Multigraph.add_edge(:d, :f)
      |> Multigraph.add_edge(:f, :d)

    assert [[:a, :c, :d], [:a, :b, :d]] == Multigraph.get_paths(g, :a, :d)
  end

  test "find shortest path" do
    g = build_basic_cyclic_graph()

    assert [:a, :b, :d, :e] = Multigraph.get_shortest_path(g, :a, :e)
  end

  test "shortest path is correct" do
    g = Generators.dag(1_000)
    dg = Generators.libgraph_to_digraph(g)

    paths = Multigraph.get_paths(g, 1, 1_000)

    shortest_g = Multigraph.dijkstra(g, 1, 1_000)
    shortest_dg = :digraph.get_short_path(dg, 1, 1_000)
    assert is_list(shortest_g)
    assert is_list(shortest_dg)

    assert is_list(paths)
    [shortest | _] = Enum.sort_by(paths, &length/1)
    shortest_len = length(shortest)

    assert ^shortest_len = length(shortest_dg)
    assert ^shortest_len = length(shortest_g)
  end

  test "shortest path for complex graph" do
    g = build_complex_graph()

    shortest_g = Multigraph.dijkstra(g, "start", "end")

    assert shortest_g ==
             [
               "start",
               "start_0",
               96,
               97,
               98,
               33,
               100,
               34,
               35,
               36,
               37,
               19,
               65,
               66,
               67,
               "end_0",
               "end"
             ]
  end

  test "shortest path for complex undirected graph" do
    g = build_complex_graph(:undirected)

    shortest_g = Multigraph.dijkstra(g, "start", "end")

    assert shortest_g ==
             ["start", "start_0", 95, 94, 93, 39, 38, 21, 69, 68, "end_0", "end"]
  end

  test "shortest path for complex graph using float weights" do
    g = build_complex_graph_float()

    shortest_g = Multigraph.dijkstra(g, "start", "end")

    assert shortest_g ==
             [
               "start",
               "start_0",
               96,
               97,
               98,
               33,
               100,
               34,
               35,
               36,
               37,
               19,
               65,
               66,
               67,
               "end_0",
               "end"
             ]
  end

  test "shortest path for complex undirected graph using float weights" do
    g = build_complex_graph_float(:undirected)

    shortest_g = Multigraph.dijkstra(g, "start", "end")

    assert shortest_g ==
             ["start", "start_0", 95, 94, 93, 39, 38, 21, 69, 68, "end_0", "end"]
  end

  test "shortest paths for complex graph using signed weights (negative and positive)" do
    g = build_complex_signed_graph()
    shortest_paths = Multigraph.bellman_ford(g, :a)
    assert shortest_paths == %{a: 0, b: -1, c: 2, d: -2, e: 1}
  end

  test "edge undirected graph v1 > v2" do
    g = build_basic_undirected_graph()
    e1 = Multigraph.edge(g, :a, :b)
    e2 = Multigraph.edge(g, :b, :a)
    assert e1 == e2
  end

  test "edge undirected graph v1 < v2" do
    g = build_basic_undirected_graph()
    e1 = Multigraph.edge(g, :b, :c)
    e2 = Multigraph.edge(g, :c, :b)
    assert e1 == e2
  end

  test "edges undirected graph v1 > v2" do
    g = build_basic_undirected_graph()
    e1 = Multigraph.edges(g, :a, :b)
    e2 = Multigraph.edges(g, :b, :a)
    assert e1 == e2
  end

  test "edges undirected graph v1 < v2" do
    g = build_basic_undirected_graph()
    e1 = Multigraph.edges(g, :b, :c)
    e2 = Multigraph.edges(g, :c, :b)
    assert e1 == e2
  end

  test "out_edges" do
    g = build_basic_acyclic_graph()
    assert [%Edge{v1: :c, v2: :d}] = Multigraph.out_edges(g, :c)
  end

  test "in_edges" do
    g = build_basic_acyclic_graph()
    assert [%Edge{v1: :b, v2: :d}, %Edge{v1: :c, v2: :d}] = Multigraph.in_edges(g, :d)
  end

  test "out_neighbors" do
    g = build_basic_acyclic_graph()
    assert [:d] = Multigraph.out_neighbors(g, :c)
  end

  test "in_neighbors" do
    g = build_basic_acyclic_graph()
    assert [:b, :c] = Multigraph.in_neighbors(g, :d)
  end

  test "cliques/1" do
    g =
      Multigraph.new(type: :undirected)
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f])
      |> Multigraph.add_edges([
        {:a, :b},
        {:b, :c},
        {:c, :d},
        {:d, :e},
        {:e, :a},
        {:e, :b},
        {:d, :f}
      ])

    cliques = Multigraph.cliques(g)
    assert [[:a, :b, :e], [:b, :c], [:c, :d], [:d, :e], [:d, :f]] = cliques
  end

  test "k_cliques/2" do
    g =
      Multigraph.new(type: :undirected)
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f])
      |> Multigraph.add_edges([
        {:a, :b},
        {:b, :c},
        {:c, :d},
        {:d, :e},
        {:e, :a},
        {:e, :b},
        {:d, :f}
      ])

    assert [[:a, :b, :e]] = Multigraph.k_cliques(g, 3)
  end

  test "k_core/2" do
    g =
      Multigraph.new(type: :undirected)
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Multigraph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:c, :e},
        {:e, :f},
        {:f, :g},
        {:f, :h}
      ])

    zero_core = Multigraph.k_core(g, 0)
    assert Multigraph.is_subgraph?(zero_core, g)
    assert Multigraph.vertices(g) == Multigraph.vertices(zero_core)

    one_core = Multigraph.k_core(g, 1)
    assert Multigraph.is_subgraph?(one_core, zero_core)
    assert Multigraph.vertices(one_core) == [:a, :b, :c, :d, :e, :f, :g, :h]

    three_core = Multigraph.k_core(g, 3)
    assert Multigraph.is_subgraph?(three_core, one_core)
    assert Multigraph.vertices(three_core) == [:a, :b, :c, :d]

    g =
      Multigraph.new(type: :undirected)
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Multigraph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:d, :e},
        {:e, :f},
        {:f, :g},
        {:g, :h},
        {:h, :i},
        {:i, :f},
        {:f, :h},
        {:i, :g}
      ])

    three_core = Multigraph.k_core(g, 3)
    assert Multigraph.vertices(three_core) == [:a, :b, :c, :d, :f, :g, :h, :i]

    g =
      Multigraph.new()
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Multigraph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :a},
        {:b, :c},
        {:b, :d},
        {:c, :a},
        {:c, :b},
        {:c, :d},
        {:d, :a},
        {:d, :b},
        {:d, :c},
        {:d, :e},
        {:e, :d},
        {:e, :f},
        {:f, :e},
        {:f, :g},
        {:g, :f},
        {:g, :h},
        {:h, :g},
        {:h, :i},
        {:i, :h},
        {:i, :f},
        {:f, :i},
        {:h, :f},
        {:f, :h},
        {:g, :i},
        {:i, :g}
      ])

    three_core = Multigraph.k_core(g, 3)
    assert Multigraph.vertices(three_core) == [:a, :b, :c, :d, :f, :g, :h, :i]
  end

  test "k_core_components/1" do
    g =
      Multigraph.new(type: :undirected)
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Multigraph.add_edges([
        {:a, :a},
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:c, :e},
        {:e, :f},
        {:f, :g},
        {:f, :h}
      ])

    components = Multigraph.k_core_components(g)
    assert [:i] = components[0]
    assert [:e, :f, :g, :h] = components[1]
    assert is_nil(components[2])
    assert [:a, :b, :c, :d] = components[3]
  end

  test "coreness/2" do
    g =
      Multigraph.new(type: :undirected)
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Multigraph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:c, :e},
        {:e, :f},
        {:f, :g},
        {:f, :h}
      ])

    assert 3 = Multigraph.coreness(g, :a)
  end

  test "degeneracy_core/1" do
    g =
      Multigraph.new(type: :undirected)
      |> Multigraph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Multigraph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:c, :e},
        {:e, :f},
        {:f, :g},
        {:f, :h}
      ])

    assert 3 = Multigraph.degeneracy(g)
    dg = Multigraph.degeneracy_core(g)
    assert [:a, :b, :c, :d] = Multigraph.vertices(dg)
  end

  @tag timeout: 120_000
  @enron_emails Path.join([__DIR__, "fixtures", "email-Enron.txt"])
  test "degeneracy/1 - Enron emails" do
    g = Multigraph.Test.Fixtures.Parser.parse(@enron_emails)
    assert 36_692 = Multigraph.num_vertices(g)
    assert 183_831 = Multigraph.num_edges(g)
    assert 43 = Multigraph.degeneracy(g)
  end

  @tag timeout: 120_000
  @hamster_friends Path.join([__DIR__, "fixtures", "petster", "edges.txt"])
  test "degeneracy/1 - Petster hamster friendships" do
    g = Multigraph.Test.Fixtures.Parser.parse(@hamster_friends)
    assert 1_858 = Multigraph.num_vertices(g)
    assert 12_534 = Multigraph.num_edges(g)
    assert 20 = Multigraph.degeneracy(g)
  end

  defp build_basic_cyclic_graph do
    Multigraph.new()
    |> Multigraph.add_vertex(:a)
    |> Multigraph.add_vertex(:b)
    |> Multigraph.add_vertex(:c)
    |> Multigraph.add_vertex(:d)
    |> Multigraph.add_vertex(:e)
    |> Multigraph.add_edge(:a, :b)
    |> Multigraph.add_edge(:a, :c)
    |> Multigraph.add_edge(:b, :c)
    |> Multigraph.add_edge(:b, :d)
    |> Multigraph.add_edge(:c, :d)
    |> Multigraph.add_edge(:c, :a)
    |> Multigraph.add_edge(:d, :e)
  end

  defp build_basic_cyclic_digraph do
    dg = :digraph.new()
    :digraph.add_vertex(dg, :a)
    :digraph.add_vertex(dg, :b)
    :digraph.add_vertex(dg, :c)
    :digraph.add_vertex(dg, :d)
    :digraph.add_vertex(dg, :e)
    :digraph.add_edge(dg, :a, :b)
    :digraph.add_edge(dg, :a, :c)
    :digraph.add_edge(dg, :b, :c)
    :digraph.add_edge(dg, :b, :d)
    :digraph.add_edge(dg, :c, :d)
    :digraph.add_edge(dg, :c, :a)
    :digraph.add_edge(dg, :d, :e)
    dg
  end

  defp build_basic_acyclic_graph do
    Multigraph.new()
    |> Multigraph.add_vertex(:a)
    |> Multigraph.add_vertex(:b)
    |> Multigraph.add_vertex(:c)
    |> Multigraph.add_vertex(:d)
    |> Multigraph.add_vertex(:e)
    |> Multigraph.add_edge(:a, :b)
    |> Multigraph.add_edge(:a, :c)
    |> Multigraph.add_edge(:b, :c)
    |> Multigraph.add_edge(:b, :d)
    |> Multigraph.add_edge(:c, :d)
    |> Multigraph.add_edge(:d, :e)
  end

  defp build_basic_acyclic_digraph do
    dg = :digraph.new()
    :digraph.add_vertex(dg, :a)
    :digraph.add_vertex(dg, :b)
    :digraph.add_vertex(dg, :c)
    :digraph.add_vertex(dg, :d)
    :digraph.add_vertex(dg, :e)
    :digraph.add_edge(dg, :a, :b)
    :digraph.add_edge(dg, :a, :c)
    :digraph.add_edge(dg, :b, :c)
    :digraph.add_edge(dg, :b, :d)
    :digraph.add_edge(dg, :c, :d)
    :digraph.add_edge(dg, :d, :e)
    dg
  end

  defp build_basic_tree_graph do
    Multigraph.new()
    |> Multigraph.add_vertex(:a)
    |> Multigraph.add_vertex(:b)
    |> Multigraph.add_vertex(:c)
    |> Multigraph.add_vertex(:d)
    |> Multigraph.add_vertex(:e)
    |> Multigraph.add_edge(:a, :b)
    |> Multigraph.add_edge(:b, :c)
    |> Multigraph.add_edge(:c, :d)
    |> Multigraph.add_edge(:c, :e)
  end

  defp build_basic_tree_digraph do
    dg = :digraph.new()
    :digraph.add_vertex(dg, :a)
    :digraph.add_vertex(dg, :b)
    :digraph.add_vertex(dg, :c)
    :digraph.add_vertex(dg, :d)
    :digraph.add_vertex(dg, :e)
    :digraph.add_edge(dg, :a, :b)
    :digraph.add_edge(dg, :b, :c)
    :digraph.add_edge(dg, :c, :d)
    :digraph.add_edge(dg, :c, :e)
    dg
  end

  defp build_basic_undirected_graph do
    Multigraph.new(type: :undirected)
    |> Multigraph.add_vertices([:a, :b, :c])
    |> Multigraph.add_edge(:a, :b)
    |> Multigraph.add_edge(:c, :b)
  end

  defp build_complex_signed_graph do
    Multigraph.new()
    |> Multigraph.add_edge(:a, :b, weight: -1)
    |> Multigraph.add_edge(:b, :e, weight: 2)
    |> Multigraph.add_edge(:e, :d, weight: -3)
    |> Multigraph.add_edge(:d, :c, weight: 5)
    |> Multigraph.add_edge(:a, :c, weight: 4)
    |> Multigraph.add_edge(:b, :c, weight: 3)
    |> Multigraph.add_edge(:b, :d, weight: 2)
    |> Multigraph.add_edge(:d, :b, weight: 1)
  end

  defp build_complex_graph(type \\ :directed) do
    Multigraph.new(type: type)
    |> Multigraph.add_edge(42, 25, weight: 2525)
    |> Multigraph.add_edge(66, 67, weight: 2254)
    |> Multigraph.add_edge(71, 72, weight: 3895)
    |> Multigraph.add_edge(79, 80, weight: 37236)
    |> Multigraph.add_edge(0, 1, weight: 1573)
    |> Multigraph.add_edge(0, 64, weight: 1595)
    |> Multigraph.add_edge(30, 31, weight: 518)
    |> Multigraph.add_edge(58, 56, weight: 431)
    |> Multigraph.add_edge(58, 60, weight: 468)
    |> Multigraph.add_edge(58, 47, weight: 1175)
    |> Multigraph.add_edge(23, 24, weight: 1807)
    |> Multigraph.add_edge(50, 56, weight: 1192)
    |> Multigraph.add_edge(50, 49, weight: 198)
    |> Multigraph.add_edge(50, 57, weight: 1192)
    |> Multigraph.add_edge(22, 23, weight: 1919)
    |> Multigraph.add_edge(22, 91, weight: 4032)
    |> Multigraph.add_edge(43, 44, weight: 255)
    |> Multigraph.add_edge(60, 46, weight: 1167)
    |> Multigraph.add_edge(60, 55, weight: 159)
    |> Multigraph.add_edge(60, 58, weight: 468)
    |> Multigraph.add_edge(36, 37, weight: 9132)
    |> Multigraph.add_edge(75, 77, weight: 2120)
    |> Multigraph.add_edge(14, 15, weight: 3483)
    |> Multigraph.add_edge(32, 33, weight: 1008)
    |> Multigraph.add_edge(41, 20, weight: 2271)
    |> Multigraph.add_edge(101, 102, weight: 27752)
    |> Multigraph.add_edge(102, 104, weight: 44964)
    |> Multigraph.add_edge(102, 103, weight: 1287)
    |> Multigraph.add_edge(104, 78, weight: 944)
    |> Multigraph.add_edge(85, 86, weight: 3029)
    |> Multigraph.add_edge(72, 73, weight: 2872)
    |> Multigraph.add_edge(88, 89, weight: 7817)
    |> Multigraph.add_edge(103, 92, weight: 2884)
    |> Multigraph.add_edge(69, 70, weight: 1719)
    |> Multigraph.add_edge(69, 21, weight: 3059)
    |> Multigraph.add_edge(13, 14, weight: 3002)
    |> Multigraph.add_edge(84, 85, weight: 3735)
    |> Multigraph.add_edge(48, 47, weight: 204)
    |> Multigraph.add_edge(34, 35, weight: 6487)
    |> Multigraph.add_edge(80, 90, weight: 29876)
    |> Multigraph.add_edge(80, 103, weight: 2047)
    |> Multigraph.add_edge(95, "start_0", weight: 3130)
    |> Multigraph.add_edge(49, 50, weight: 198)
    |> Multigraph.add_edge(38, 39, weight: 11222)
    |> Multigraph.add_edge(37, 19, weight: 5284)
    |> Multigraph.add_edge(68, 69, weight: 2476)
    |> Multigraph.add_edge(77, 78, weight: 2138)
    |> Multigraph.add_edge(86, 87, weight: 8289)
    |> Multigraph.add_edge(61, 64, weight: 508)
    |> Multigraph.add_edge(61, 46, weight: 1181)
    |> Multigraph.add_edge(61, 59, weight: 490)
    |> Multigraph.add_edge("end_0", 68, weight: 288)
    |> Multigraph.add_edge("end_0", "end", weight: 0)
    |> Multigraph.add_edge(87, 88, weight: 5729)
    |> Multigraph.add_edge(94, 95, weight: 2665)
    |> Multigraph.add_edge(74, 75, weight: 1641)
    |> Multigraph.add_edge(12, 13, weight: 5014)
    |> Multigraph.add_edge(25, 30, weight: 1645)
    |> Multigraph.add_edge(25, 24, weight: 248)
    |> Multigraph.add_edge(15, 1, weight: 2005)
    |> Multigraph.add_edge(4, 12, weight: 3150)
    |> Multigraph.add_edge(54, 56, weight: 547)
    |> Multigraph.add_edge(54, 52, weight: 1332)
    |> Multigraph.add_edge(54, 27, weight: 2095)
    |> Multigraph.add_edge(70, 71, weight: 22390)
    |> Multigraph.add_edge(29, 32, weight: 2449)
    |> Multigraph.add_edge(59, 47, weight: 1190)
    |> Multigraph.add_edge(59, 57, weight: 418)
    |> Multigraph.add_edge(59, 61, weight: 490)
    |> Multigraph.add_edge(35, 36, weight: 6814)
    |> Multigraph.add_edge(52, 51, weight: 195)
    |> Multigraph.add_edge(52, 54, weight: 1332)
    |> Multigraph.add_edge(52, 55, weight: 1186)
    |> Multigraph.add_edge("start", "start_0", weight: 0)
    |> Multigraph.add_edge(78, 84, weight: 3418)
    |> Multigraph.add_edge(78, 79, weight: 6596)
    |> Multigraph.add_edge("start_0", 96, weight: 120)
    |> Multigraph.add_edge(39, 93, weight: 4220)
    |> Multigraph.add_edge(39, 40, weight: 5082)
    |> Multigraph.add_edge(45, 46, weight: 235)
    |> Multigraph.add_edge(18, 29, weight: 600)
    |> Multigraph.add_edge(73, 74, weight: 788)
    |> Multigraph.add_edge(98, 41, weight: 2187)
    |> Multigraph.add_edge(98, 33, weight: 1496)
    |> Multigraph.add_edge(93, 94, weight: 13132)
    |> Multigraph.add_edge(20, 42, weight: 566)
    |> Multigraph.add_edge(67, "end_0", weight: 483)
    |> Multigraph.add_edge(64, 0, weight: 1595)
    |> Multigraph.add_edge(64, 44, weight: 1174)
    |> Multigraph.add_edge(64, 61, weight: 508)
    |> Multigraph.add_edge(96, 13, weight: 2865)
    |> Multigraph.add_edge(96, 97, weight: 2773)
    |> Multigraph.add_edge(46, 60, weight: 1167)
    |> Multigraph.add_edge(46, 45, weight: 235)
    |> Multigraph.add_edge(46, 61, weight: 1181)
    |> Multigraph.add_edge(19, 70, weight: 2732)
    |> Multigraph.add_edge(19, 65, weight: 1911)
    |> Multigraph.add_edge(65, 66, weight: 2886)
    |> Multigraph.add_edge(51, 52, weight: 195)
    |> Multigraph.add_edge(33, 100, weight: 4369)
    |> Multigraph.add_edge(89, 21, weight: 3165)
    |> Multigraph.add_edge(89, 65, weight: 3221)
    |> Multigraph.add_edge(1, 0, weight: 1573)
    |> Multigraph.add_edge(1, 3, weight: 1999)
    |> Multigraph.add_edge(100, 93, weight: 2056)
    |> Multigraph.add_edge(100, 34, weight: 4038)
    |> Multigraph.add_edge(55, 60, weight: 159)
    |> Multigraph.add_edge(55, 52, weight: 1186)
    |> Multigraph.add_edge(55, 57, weight: 358)
    |> Multigraph.add_edge(21, 38, weight: 16458)
    |> Multigraph.add_edge(40, 41, weight: 5104)
    |> Multigraph.add_edge(3, 4, weight: 3476)
    |> Multigraph.add_edge(91, 22, weight: 4032)
    |> Multigraph.add_edge(91, 101, weight: 1970)
    |> Multigraph.add_edge(44, 64, weight: 1174)
    |> Multigraph.add_edge(44, 57, weight: 1129)
    |> Multigraph.add_edge(44, 43, weight: 255)
    |> Multigraph.add_edge(24, 22, weight: 1820)
    |> Multigraph.add_edge(24, 25, weight: 248)
    |> Multigraph.add_edge(27, 54, weight: 2095)
    |> Multigraph.add_edge(27, 29, weight: 1205)
    |> Multigraph.add_edge(57, 44, weight: 1129)
    |> Multigraph.add_edge(57, 50, weight: 1192)
    |> Multigraph.add_edge(57, 55, weight: 358)
    |> Multigraph.add_edge(57, 59, weight: 418)
    |> Multigraph.add_edge(92, 38, weight: 3589)
    |> Multigraph.add_edge(47, 48, weight: 204)
    |> Multigraph.add_edge(47, 59, weight: 1190)
    |> Multigraph.add_edge(47, 58, weight: 1175)
    |> Multigraph.add_edge(56, 50, weight: 1192)
    |> Multigraph.add_edge(56, 54, weight: 547)
    |> Multigraph.add_edge(56, 58, weight: 431)
    |> Multigraph.add_edge(90, 91, weight: 2301)
    |> Multigraph.add_edge(31, 18, weight: 861)
    |> Multigraph.add_edge(31, 27, weight: 1178)
    |> Multigraph.add_edge(97, 98, weight: 13465)
  end

  defp build_complex_graph_float(type \\ :directed) do
    build_complex_graph(type)
    |> Multigraph.edges()
    |> Enum.reduce(Multigraph.new(type: type), fn %Multigraph.Edge{weight: weight} = edge, acc ->
      acc
      |> Multigraph.add_edge(%Multigraph.Edge{edge | weight: weight / 1000})
    end)
  end
end
