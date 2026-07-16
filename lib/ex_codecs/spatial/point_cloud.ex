defmodule ExCodecs.Spatial.PointCloud do
  @moduledoc """
  A collection of `%ExCodecs.Spatial.Point{}` values with bounds and metadata.

  ## Fields

    * `:points` — `[Point.t()]`; defaults to `[]`. Ordering is preserved.
      Coordinate units and conventions are defined by the application.
    * `:bounds` — `Bounds.t() | nil`; defaults to `nil`. `new/2` computes an
      axis-aligned box by default; `nil` also represents an empty cloud or
      deliberately uncomputed bounds.
    * `:metadata` — `Metadata.t()`; defaults to `%Metadata{}`.

  ## Example

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> cloud = PointCloud.new([Point.new(0, 0, 0), Point.new(2, 1, -1)])
      iex> {PointCloud.size(cloud), cloud.bounds.max_x}
      {2, 2.0}
  """

  alias ExCodecs.Spatial.{Bounds, Metadata, Point}

  @typedoc """
  A point cloud. See the module documentation for every field, its default,
  units or conventions, and a construction example.
  """
  @type t :: %__MODULE__{
          points: [Point.t()],
          bounds: Bounds.t() | nil,
          metadata: Metadata.t()
        }

  defstruct points: [],
            bounds: nil,
            metadata: %Metadata{}

  @doc """
  Builds a point cloud from a list of points.

  ## Arguments

    * `points` — list of `%Point{}`
    * `opts`:
      * `:compute_bounds` — boolean (default `true`)
      * `:bounds` — explicit `%Bounds{}` (overrides compute)
      * `:metadata` — `%Metadata{}`

  ## Returns

  `%PointCloud{}`

  ## Raises

  * `FunctionClauseError` if `points` is not a list, an element is not
    point-like while bounds are computed, or `opts` is not a keyword list.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> cloud = PointCloud.new([Point.new(0, 0, 0), Point.new(1, 1, 1)])
      iex> PointCloud.size(cloud)
      2
  """
  @spec new([Point.t()], keyword()) :: t()
  def new(points, opts \\ []) when is_list(points) do
    compute_bounds? = Keyword.get(opts, :compute_bounds, true)
    metadata = Keyword.get(opts, :metadata, %Metadata{})
    bounds = Keyword.get(opts, :bounds)

    %__MODULE__{
      points: points,
      bounds: bounds || if(compute_bounds?, do: Bounds.from_points(points), else: nil),
      metadata: metadata
    }
  end

  @doc """
  Number of points.

  ## Arguments

    * `cloud` — `%PointCloud{}`

  ## Returns

  non-negative integer

  ## Raises

  * `FunctionClauseError` if `cloud` is not a `%PointCloud{}`.
  * `ArgumentError` if a manually constructed cloud has a non-list `:points`.

  ## Examples

      iex> ExCodecs.Spatial.PointCloud.size(ExCodecs.Spatial.PointCloud.new([]))
      0
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{points: points}), do: length(points)

  @doc """
  Returns `true` when every point has color (empty cloud → `false`).

  ## Arguments

    * `cloud` — `%PointCloud{}`

  ## Returns

  boolean

  ## Raises

  * `FunctionClauseError` if `cloud` is not a `%PointCloud{}`, or if any
    point has an unsupported `:color` value.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> PointCloud.colored?(PointCloud.new([Point.new(0, 0, 0, color: {1, 2, 3})]))
      true
  """
  @spec colored?(t()) :: boolean()
  def colored?(%__MODULE__{points: []}), do: false
  def colored?(%__MODULE__{points: points}), do: Enum.all?(points, &Point.colored?/1)

  @doc """
  Returns `true` when every point has a normal (empty → `false`).

  ## Arguments

    * `cloud` — `%PointCloud{}`

  ## Returns

  boolean

  ## Raises

  * `FunctionClauseError` if `cloud` is not a `%PointCloud{}`, or if any
    point has an unsupported `:normal` value.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> PointCloud.has_normals?(PointCloud.new([Point.new(0, 0, 0)]))
      false
  """
  @spec has_normals?(t()) :: boolean()
  def has_normals?(%__MODULE__{points: []}), do: false
  def has_normals?(%__MODULE__{points: points}), do: Enum.all?(points, &Point.has_normal?/1)

  @doc """
  Recomputes axis-aligned bounds from points.

  ## Arguments

    * `cloud` — `%PointCloud{}`

  ## Returns

  `%PointCloud{}` with updated `bounds`

  ## Raises

  * `FunctionClauseError` if `cloud` is not a `%PointCloud{}` or a point is
    not a supported point-like value.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> cloud = PointCloud.new([Point.new(0, 0, 0)], compute_bounds: false)
      iex> PointCloud.with_bounds(cloud).bounds != nil
      true
  """
  @spec with_bounds(t()) :: t()
  def with_bounds(%__MODULE__{points: points} = cloud) do
    %{cloud | bounds: Bounds.from_points(points)}
  end

  @doc """
  Appends one point and expands bounds.

  Prefer `new/1` or `add_points/2` for bulk inserts (`++` is O(n)).

  ## Arguments

    * `cloud` — `%PointCloud{}`
    * `point` — `%Point{}`

  ## Returns

  Updated `%PointCloud{}`

  ## Raises

  * `FunctionClauseError` unless the arguments are a `%PointCloud{}` and a
    `%Point{}`, or if existing bounds are neither `nil` nor `%Bounds{}`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> c = PointCloud.new([])
      iex> PointCloud.size(PointCloud.add_point(c, Point.new(1, 2, 3)))
      1
  """
  @spec add_point(t(), Point.t()) :: t()
  def add_point(%__MODULE__{points: points, bounds: bounds} = cloud, %Point{} = point) do
    new_bounds =
      case bounds do
        nil ->
          Bounds.from_points([point])

        %Bounds{} = b ->
          {x, y, z} = Point.coords(point)

          %Bounds{
            min_x: min(b.min_x, x),
            min_y: min(b.min_y, y),
            min_z: min(b.min_z, z),
            max_x: max(b.max_x, x),
            max_y: max(b.max_y, y),
            max_z: max(b.max_z, z)
          }
      end

    %{cloud | points: points ++ [point], bounds: new_bounds}
  end

  @doc """
  Appends many points (via repeated `add_point/2`).

  ## Arguments

    * `cloud` — `%PointCloud{}`
    * `new_points` — list of `%Point{}`

  ## Returns

  Updated `%PointCloud{}`

  ## Raises

  * `FunctionClauseError` unless `cloud` is a `%PointCloud{}` and
    `new_points` is a list, or if any element is not a `%Point{}`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> c = PointCloud.add_points(PointCloud.new([]), [Point.new(0, 0, 0), Point.new(1, 1, 1)])
      iex> PointCloud.size(c)
      2
  """
  @spec add_points(t(), [Point.t()]) :: t()
  def add_points(%__MODULE__{} = cloud, new_points) when is_list(new_points) do
    Enum.reduce(new_points, cloud, fn p, acc -> add_point(acc, p) end)
  end
end
