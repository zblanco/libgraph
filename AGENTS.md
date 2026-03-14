# Libgraph Agent Guide

Libgraph is a high-performance graph datastructure library for Elixir projects. It provides an implementation of directed and undirected graphs (both acyclic and cyclic), a priority queue oriented towards graph algorithms, pathfinding/shortest-path algorithms, graph serialization (including Graphviz DOT), and reducer-based traversal.

Libgraph is designed as a pure functional alternative to Erlang's `:digraph` — it requires no ETS tables, is inspect-friendly, supports weighted and labeled edges, multigraphs, and undirected graphs. The graph struct uses maps of vertex ids for efficient construction and querying.

## Build/Test Commands
- `mix test` - Run all tests
- `mix test test/specific_test.exs` - Run specific test file
- `mix test test/specific_test.exs:123` - Run specific test line
- `mix compile` - Compile the project
- `mix format` - Format code according to .formatter.exs
- `mix deps.get` - Get dependencies
- `mix clean` - Clean compiled files
- `mix bench` - Run all benchmarks (requires `:bench` env)

## Architecture
- **Core module**: `Graph` (`lib/graph.ex`) — main API for creating, modifying, and querying graphs
- **Edge**: `Graph.Edge` (`lib/edge.ex`) — edge struct
- **PriorityQueue**: `PriorityQueue` (`lib/priority_queue.ex`) — min-priority queue for graph algorithms
- **Pathfinding**: `Graph.Pathfinding` and modules under `lib/graph/pathfindings/` — shortest path, A*, Dijkstra, BFS
- **Reducers**: `Graph.Reducer` and modules under `lib/graph/reducers/` — map/reduce traversal over graphs
- **Serializers**: `Graph.Serializer` behaviour and modules under `lib/graph/serializers/` — e.g. DOT format
- **Utils**: `Graph.Utils` — vertex id generation, edge label helpers
- **Inspect**: `Graph.Inspect` — `Inspect` protocol implementation for `Graph`
- **Graph struct fields**: `vertices`, `in_edges`, `out_edges`, `edges`, `edge_index`, `vertex_labels`, `type`, `vertex_identifier`, `partition_by`, `multigraph`

## Code Style & Conventions
- Use `mix format` for automatic formatting
- Follow Elixir naming: snake_case for variables/functions, PascalCase for modules
- Import order: Standard library, external deps, internal modules (alias first)  
- Pattern matching preferred over conditionals
- Use `with` for multiple success/failure operations
- Module attributes for compile-time configuration
- Behaviours for extensibility (see `Graph.Serializer`, `Graph.Reducer`)

## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`
- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field`
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
