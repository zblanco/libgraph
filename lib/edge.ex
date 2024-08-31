defmodule Graph.Edge do
  @moduledoc """
  This module defines the struct used to represent edges and associated metadata about them.

  Used internally, `v1` and `v2` typically hold vertex ids, not the vertex itself, but all
  public APIs which return `Graph.Edge` structs, return them with the actual vertices.
  """
  defstruct v1: nil,
            v2: nil,
            weight: 1,
            label: nil,
            properties: %{}

  @type t :: %__MODULE__{
          v1: Graph.vertex(),
          v2: Graph.vertex(),
          weight: integer | float,
          label: term,
          properties: map
        }
  @type edge_opt ::
          {:weight, integer | float}
          | {:label, term}
          | {:properties, map}
  @type edge_opts :: [edge_opt]

  @doc """
  Defines a new edge and accepts optional values for weight and label.
  The defaults of a weight of 1 and no label will be used if the options do
  not specify otherwise.

  An error will be thrown if weight is not an integer or float.

  ## Example

      iex> Graph.new |> Graph.add_edge(Graph.Edge.new(:a, :b, weight: "1"))
      ** (ArgumentError) invalid value for :weight, must be an integer
  """
  @spec new(Graph.vertex(), Graph.vertex()) :: t
  @spec new(Graph.vertex(), Graph.vertex(), [edge_opt]) :: t | no_return
  def new(v1, v2, opts \\ []) when is_list(opts) do
    {weight, opts} = Keyword.pop(opts, :weight, 1)
    {label, opts} = Keyword.pop(opts, :label)

    %__MODULE__{
      v1: v1,
      v2: v2,
      weight: weight,
      label: label,
      properties: Keyword.get(opts, :properties, %{})
    }
  end

  @doc false
  def options_to_meta(opts) when is_list(opts) do
    label = Keyword.get(opts, :label)
    weight = Keyword.get(opts, :weight, 1)
    properties = Keyword.get(opts, :properties, %{})

    case {label, %{weight: weight, properties: properties}} do
      {label, %{weight: w} = meta} when is_number(w) ->
        {label, meta}

      _other ->
        raise ArgumentError, message: "invalid value for :weight, must be an integer"
    end
  end

  def options_to_meta(nil), do: nil

  @doc false
  def to_meta(%__MODULE__{label: label, weight: weight}), do: {label, weight}
end
