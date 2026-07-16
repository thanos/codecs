defmodule ExCodecs.Spatial.GaussianCloud do
  @moduledoc """
  A collection of `%ExCodecs.Spatial.Gaussian{}` values for codec interchange.

  ## Fields

    * `:gaussians` — `[Gaussian.t()]`; defaults to `[]`. Ordering is preserved.
      Positions use application-defined Cartesian units.
    * `:bounds` — `Bounds.t() | nil`; defaults to `nil`. `new/2` computes
      axis-aligned bounds from Gaussian centers by default; extents do not
      include each Gaussian's scale.
    * `:metadata` — `Metadata.t()`; defaults to `%Metadata{}`.

  ## Example

      iex> alias ExCodecs.Spatial.{Gaussian, GaussianCloud}
      iex> cloud = GaussianCloud.new([Gaussian.new({-1, 0, 0}), Gaussian.new({2, 0, 0})])
      iex> {GaussianCloud.size(cloud), cloud.bounds.min_x, cloud.bounds.max_x}
      {2, -1.0, 2.0}
  """

  alias ExCodecs.Spatial.{Bounds, Gaussian, Metadata}

  @typedoc """
  A Gaussian cloud. See the module documentation for every field, its default,
  units or conventions, and a construction example.
  """
  @type t :: %__MODULE__{
          gaussians: [Gaussian.t()],
          bounds: Bounds.t() | nil,
          metadata: Metadata.t()
        }

  defstruct gaussians: [],
            bounds: nil,
            metadata: %Metadata{}

  @doc """
  Builds a Gaussian cloud.

  ## Arguments

    * `gaussians` — `[Gaussian.t()]`; the supplied list is retained.
    * `opts` — a keyword list with:
      * `:compute_bounds` — any truthy/falsy term; defaults to `true`.
      * `:bounds` — `Bounds.t() | nil`; a truthy value overrides computation.
      * `:metadata` — `Metadata.t()`; defaults to `%Metadata{}`.

  ## Returns

  `%GaussianCloud{}`

  ## Raises

  * `FunctionClauseError` if `gaussians` is not a list, an extracted position
    is not a numeric 3-tuple, or `opts` is not a keyword list.
  * `KeyError` or `BadMapError` if an item does not expose `:position`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Gaussian, GaussianCloud}
      iex> c = GaussianCloud.new([Gaussian.new({0.0, 0.0, 0.0})])
      iex> GaussianCloud.size(c)
      1
  """
  @spec new([Gaussian.t()], keyword()) :: t()
  def new(gaussians, opts \\ []) when is_list(gaussians) do
    compute_bounds? = Keyword.get(opts, :compute_bounds, true)
    metadata = Keyword.get(opts, :metadata, %Metadata{})
    bounds = Keyword.get(opts, :bounds)

    positions = Enum.map(gaussians, & &1.position)

    %__MODULE__{
      gaussians: gaussians,
      bounds: bounds || if(compute_bounds?, do: Bounds.from_points(positions), else: nil),
      metadata: metadata
    }
  end

  @doc """
  Number of Gaussians.

  ## Arguments

    * `cloud` — `%GaussianCloud{}`

  ## Returns

  non-negative integer

  ## Raises

  * `FunctionClauseError` if `cloud` is not a `%GaussianCloud{}`.
  * `ArgumentError` if a manually constructed cloud has a non-list
    `:gaussians` field.

  ## Examples

      iex> ExCodecs.Spatial.GaussianCloud.size(ExCodecs.Spatial.GaussianCloud.new([]))
      0
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{gaussians: gaussians}), do: length(gaussians)

  @doc """
  Recomputes bounds from Gaussian positions.

  ## Arguments

    * `cloud` — `%GaussianCloud{}`

  ## Returns

  Updated `%GaussianCloud{}`

  ## Raises

  * `FunctionClauseError` if `cloud` is not a `%GaussianCloud{}` or an
    extracted position is not a numeric 3-tuple.
  * `KeyError` or `BadMapError` if an item does not expose `:position`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Gaussian, GaussianCloud}
      iex> c = GaussianCloud.new([Gaussian.new({1.0, 2.0, 3.0})], compute_bounds: false)
      iex> GaussianCloud.with_bounds(c).bounds != nil
      true
  """
  @spec with_bounds(t()) :: t()
  def with_bounds(%__MODULE__{gaussians: gaussians} = cloud) do
    positions = Enum.map(gaussians, & &1.position)
    %{cloud | bounds: Bounds.from_points(positions)}
  end
end
