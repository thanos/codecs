defmodule ExCodecs.Spatial.Point do
  @moduledoc """
  A 3D point with optional color, surface normal, and attributes.

  ## Fields

    * `:x`, `:y`, `:z` — `float()` Cartesian coordinates. `new/4` requires
      them and converts numbers to floats; the struct defaults are `0.0`.
      Units are application-defined and must be consistent within a cloud.
    * `:color` — `rgb() | rgba() | nil`; defaults to `nil`. Channels are
      non-negative integers conventionally in `0..255`; alpha is last.
    * `:normal` — `normal() | nil`; defaults to `nil`. Components follow the
      same axis convention as the coordinates and are normally unit length,
      though this module does not normalize them.
    * `:attributes` — `attributes()`; defaults to `%{}`. Keys are atoms or
      strings and values are numbers or binaries.

  ## Example

      iex> ExCodecs.Spatial.Point.new(1, 2.5, -3, color: {255, 128, 0}, normal: {0.0, 0.0, 1.0})
      %ExCodecs.Spatial.Point{
        x: 1.0,
        y: 2.5,
        z: -3.0,
        color: {255, 128, 0},
        normal: {0.0, 0.0, 1.0},
        attributes: %{}
      }
  """

  @typedoc """
  An RGB color tuple `{red, green, blue}`. Channels are non-negative integers,
  conventionally in `0..255`; that range is not enforced. For example,
  `{255, 128, 0}` represents orange.
  """
  @type rgb :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @typedoc """
  An RGBA color tuple `{red, green, blue, alpha}`. Channels are non-negative
  integers, conventionally in `0..255`; that range is not enforced. For
  example, `{0, 64, 255, 128}` is a half-transparent blue.
  """
  @type rgba :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @typedoc """
  A surface-normal vector `{nx, ny, nz}` in the point coordinate convention.
  Unit length is conventional but is not enforced. For example,
  `{0.0, 0.0, 1.0}` points along the positive Z axis.
  """
  @type normal :: {float(), float(), float()}
  @typedoc """
  User attributes keyed by atoms or strings, with numeric or binary values.
  For example, `%{"intensity" => 0.82, :classification => 2}` stores two
  application-defined point attributes.
  """
  @type attributes :: %{optional(atom() | String.t()) => number() | binary()}

  @typedoc """
  A spatial point. See the module documentation for every field, its default,
  units or conventions, and a construction example.
  """
  @type t :: %__MODULE__{
          x: float(),
          y: float(),
          z: float(),
          color: rgb() | rgba() | nil,
          normal: normal() | nil,
          attributes: attributes()
        }

  @enforce_keys [:x, :y, :z]
  defstruct x: 0.0,
            y: 0.0,
            z: 0.0,
            color: nil,
            normal: nil,
            attributes: %{}

  @doc """
  Builds a point from coordinates and optional fields.

  ## Arguments

    * `x`, `y`, `z` — numbers (stored as floats)
    * `opts`:
      * `:color` — `rgb` or `rgba` tuple, or `nil`
      * `:normal` — `{nx, ny, nz}` or `nil`
      * `:attributes` — map (default `%{}`)

  ## Returns

  `%ExCodecs.Spatial.Point{}`

  ## Raises

  * `FunctionClauseError` if a coordinate is not numeric, or if `opts` is not
    a keyword list accepted by `Keyword.get/3`.

  ## Examples

      iex> p = ExCodecs.Spatial.Point.new(1.0, 2.0, 3.0)
      iex> {p.x, p.y, p.z}
      {1.0, 2.0, 3.0}

      iex> p = ExCodecs.Spatial.Point.new(0.0, 0.0, 0.0, color: {255, 128, 0})
      iex> p.color
      {255, 128, 0}
  """
  @spec new(number(), number(), number(), keyword()) :: t()
  def new(x, y, z, opts \\ []) when is_number(x) and is_number(y) and is_number(z) do
    %__MODULE__{
      x: x * 1.0,
      y: y * 1.0,
      z: z * 1.0,
      color: Keyword.get(opts, :color),
      normal: Keyword.get(opts, :normal),
      attributes: Keyword.get(opts, :attributes, %{})
    }
  end

  @doc """
  Returns `{x, y, z}`.

  ## Arguments

    * `point` — `%Point{}`

  ## Returns

  `{float(), float(), float()}`

  ## Raises

  * `FunctionClauseError` if `point` is not a `%Point{}`.

  ## Examples

      iex> ExCodecs.Spatial.Point.coords(ExCodecs.Spatial.Point.new(1, 2, 3))
      {1.0, 2.0, 3.0}
  """
  @spec coords(t()) :: {float(), float(), float()}
  def coords(%__MODULE__{x: x, y: y, z: z}), do: {x, y, z}

  @doc """
  Returns whether the point has RGB or RGBA color.

  ## Arguments

    * `point` — `%Point{}`

  ## Returns

  `true` | `false`

  ## Raises

  * `FunctionClauseError` if the argument is not a `%Point{}` or its `:color`
    is neither `nil`, a 3-tuple, nor a 4-tuple.

  ## Examples

      iex> ExCodecs.Spatial.Point.colored?(ExCodecs.Spatial.Point.new(0, 0, 0))
      false
      iex> ExCodecs.Spatial.Point.colored?(ExCodecs.Spatial.Point.new(0, 0, 0, color: {1, 2, 3}))
      true
  """
  @spec colored?(t()) :: boolean()
  def colored?(%__MODULE__{color: nil}), do: false
  def colored?(%__MODULE__{color: {_r, _g, _b}}), do: true
  def colored?(%__MODULE__{color: {_r, _g, _b, _a}}), do: true

  @doc """
  Returns whether the point has a surface normal.

  ## Arguments

    * `point` — `%Point{}`

  ## Returns

  `true` | `false`

  ## Raises

  * `FunctionClauseError` if the argument is not a `%Point{}` or its `:normal`
    is neither `nil` nor a 3-tuple.

  ## Examples

      iex> ExCodecs.Spatial.Point.has_normal?(ExCodecs.Spatial.Point.new(0, 0, 0))
      false
      iex> ExCodecs.Spatial.Point.has_normal?(ExCodecs.Spatial.Point.new(0, 0, 0, normal: {0.0, 1.0, 0.0}))
      true
  """
  @spec has_normal?(t()) :: boolean()
  def has_normal?(%__MODULE__{normal: nil}), do: false
  def has_normal?(%__MODULE__{normal: {_nx, _ny, _nz}}), do: true
end
