defmodule ExCodecs.Spatial.Bounds do
  @moduledoc """
  An axis-aligned bounding box.

  ## Fields

    * `:min_x`, `:min_y`, `:min_z` — `float()` lower Cartesian limits.
    * `:max_x`, `:max_y`, `:max_z` — `float()` upper Cartesian limits.

  All six fields are enforced when constructing a literal struct. Their raw
  `defstruct` defaults are `nil`, but `new/2` stores floats. Units are
  application-defined and must match the bounded coordinates. Bounds are
  inclusive, and this module does not require each minimum to be no greater
  than its corresponding maximum.

  ## Example

      iex> alias ExCodecs.Spatial.Bounds
      iex> bounds = Bounds.new({-1, 0, 2}, {4, 5, 8})
      iex> {Bounds.center(bounds), Bounds.contains?(bounds, {0, 1, 3})}
      {{1.5, 2.5, 5.0}, true}
  """

  @typedoc """
  An inclusive axis-aligned bounding box. See the module documentation for
  every field, defaults, units and conventions, and a construction example.
  """
  @type t :: %__MODULE__{
          min_x: float(),
          min_y: float(),
          min_z: float(),
          max_x: float(),
          max_y: float(),
          max_z: float()
        }

  @enforce_keys [:min_x, :min_y, :min_z, :max_x, :max_y, :max_z]
  defstruct [:min_x, :min_y, :min_z, :max_x, :max_y, :max_z]

  @doc """
  Builds bounds from min and max corners.

  ## Arguments

    * `min` — numeric `{min_x, min_y, min_z}` lower corner in
      application-defined coordinate units.
    * `max` — numeric `{max_x, max_y, max_z}` upper corner in the same units.

  ## Returns

  `%Bounds{}`

  ## Raises

  * `FunctionClauseError` if either argument is not a 3-tuple.
  * `ArithmeticError` if any component is not numeric.

  ## Examples

      iex> b = ExCodecs.Spatial.Bounds.new({0, 0, 0}, {1, 2, 3})
      iex> b.max_z
      3.0
  """
  @spec new(
          {number(), number(), number()},
          {number(), number(), number()}
        ) :: t()
  def new({min_x, min_y, min_z}, {max_x, max_y, max_z}) do
    %__MODULE__{
      min_x: min_x * 1.0,
      min_y: min_y * 1.0,
      min_z: min_z * 1.0,
      max_x: max_x * 1.0,
      max_y: max_y * 1.0,
      max_z: max_z * 1.0
    }
  end

  @doc """
  Computes bounds from points or `{x,y,z}` tuples.

  ## Arguments

    * `points` — `Enumerable.t()` of maps/structs with numeric `:x`, `:y`,
      and `:z` fields, or numeric `{x, y, z}` tuples.

  ## Returns

  `%Bounds{}` or `nil` if empty

  ## Raises

  * `Protocol.UndefinedError` if `points` is not enumerable.
  * `FunctionClauseError` if an element is not a supported point-like value.
  * `ArithmeticError` if a map/struct coordinate is not numeric.

  ## Examples

      iex> ExCodecs.Spatial.Bounds.from_points([])
      nil
      iex> b = ExCodecs.Spatial.Bounds.from_points([{0, 0, 0}, {1, 1, 1}])
      iex> b.max_x
      1.0
  """
  @spec from_points(Enumerable.t()) :: t() | nil
  def from_points(points) do
    Enum.reduce(points, nil, fn point, acc ->
      {x, y, z} = coords(point)

      case acc do
        nil ->
          new({x, y, z}, {x, y, z})

        %__MODULE__{} = b ->
          %__MODULE__{
            min_x: min(b.min_x, x),
            min_y: min(b.min_y, y),
            min_z: min(b.min_z, z),
            max_x: max(b.max_x, x),
            max_y: max(b.max_y, y),
            max_z: max(b.max_z, z)
          }
      end
    end)
  end

  @doc """
  Center point of the box.

  ## Arguments

    * `bounds` — `%Bounds{}`

  ## Returns

  `{cx, cy, cz}` floats

  ## Raises

  * `FunctionClauseError` if `bounds` is not a `%Bounds{}`.
  * `ArithmeticError` if a manually constructed bounds has non-numeric fields.

  ## Examples

      iex> ExCodecs.Spatial.Bounds.center(ExCodecs.Spatial.Bounds.new({0, 0, 0}, {2, 2, 2}))
      {1.0, 1.0, 1.0}
  """
  @spec center(t()) :: {float(), float(), float()}
  def center(%__MODULE__{} = b) do
    {(b.min_x + b.max_x) / 2.0, (b.min_y + b.max_y) / 2.0, (b.min_z + b.max_z) / 2.0}
  end

  @doc """
  Extents `{dx, dy, dz}`.

  ## Arguments

    * `bounds` — `%Bounds{}`

  ## Returns

  `{float(), float(), float()}`

  ## Raises

  * `FunctionClauseError` if `bounds` is not a `%Bounds{}`.
  * `ArithmeticError` if a manually constructed bounds has non-numeric fields.

  ## Examples

      iex> ExCodecs.Spatial.Bounds.size(ExCodecs.Spatial.Bounds.new({0, 0, 0}, {1, 2, 3}))
      {1.0, 2.0, 3.0}
  """
  @spec size(t()) :: {float(), float(), float()}
  def size(%__MODULE__{} = b) do
    {b.max_x - b.min_x, b.max_y - b.min_y, b.max_z - b.min_z}
  end

  @doc """
  Whether `{x,y,z}` lies inside or on the box.

  ## Arguments

    * `bounds` — `%Bounds{}`
    * `point` — `{number(), number(), number()}` in the bounds' coordinate
      units.

  ## Returns

  boolean

  ## Raises

  * `FunctionClauseError` unless the arguments are a `%Bounds{}` and a
    3-tuple. Elixir term ordering is otherwise used for non-numeric values
    supplied outside the documented types.

  ## Examples

      iex> b = ExCodecs.Spatial.Bounds.new({0, 0, 0}, {1, 1, 1})
      iex> ExCodecs.Spatial.Bounds.contains?(b, {0.5, 0.5, 0.5})
      true
  """
  @spec contains?(t(), {number(), number(), number()}) :: boolean()
  def contains?(%__MODULE__{} = b, {x, y, z}) do
    x >= b.min_x and x <= b.max_x and
      y >= b.min_y and y <= b.max_y and
      z >= b.min_z and z <= b.max_z
  end

  defp coords(%{x: x, y: y, z: z}), do: {x * 1.0, y * 1.0, z * 1.0}

  defp coords({x, y, z}) when is_number(x) and is_number(y) and is_number(z),
    do: {x * 1.0, y * 1.0, z * 1.0}
end
